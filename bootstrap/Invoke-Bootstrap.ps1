#Requires -Version 7.2
<#
.SYNOPSIS
    Interactive, resumable bootstrap wrapper for the Azure subscription
    vending skeleton -- with built-in destroy / teardown mode.

.DESCRIPTION
    Single entry point for the bootstrap LIFECYCLE: create (default) and
    destroy (`-Destroy`). Inspired by ALZ Accelerator's `Deploy-Accelerator`.

    BOOTSTRAP MODE (default) -- replaces the manual "Copy-Item
    terraform.tfvars.example -> edit -> terraform init/plan/apply"
    sequence with a guided wizard.

      Phases (control with -Phase):
        preflight   Tool versions, gh scopes, az tenant binding
        configure   Prompt for every bootstrap input (grouped); persist to JSON
        validate    Talk to Azure / GitHub APIs to verify the inputs are sane
        terraform   init -> plan -> apply (apply requires -AutoApprove)
        all         All four in order (default)

    DESTROY MODE (-Destroy) -- undo a bootstrap. Use when a bootstrap
    was applied by mistake (wrong tenant, wrong repo, typo, abandoned
    POC) and you want to start over.

      Two paths chosen automatically:
        1. Preferred -- `terraform destroy` when local
           `bootstrap/terraform.tfstate` exists. Cleanest.
        2. Fallback -- force-delete by name via `az` + `gh` API calls
           when state is lost (workstation rebuild, deleted state file).
           Driven by the JSON sidecar.

      Always runs preflight -> discover -> destroy (no -Phase needed).
      `-WhatIf` discovers what exists and prints what would happen
      without performing any deletes.

      Safety rails (regardless of -AutoApprove):
        - REFUSES to run if `az account show --query tenantId` doesn't
          match `tenant_id` in the sidecar (cross-tenant guard).
        - State container only deleted when EMPTY and only with
          -IncludeStateContainer (it holds vended-sub state, not just
          bootstrap state).
        - GitHub repo only deleted with -IncludeGitHubRepo.
        - Billing-scope SubscriptionCreator role is NEVER touched -- the
          script prints per-agreement-type (EA/MCA/MPA) manual
          revocation commands instead.

    LOCAL CLEANUP (-CleanBootstrapFolder) -- wipe local Terraform state
    + the wizard's sidecar files. Works standalone (just the cleanup)
    or chained with destroy (destroy + clean).

    Source of truth:
      .bootstrap-inputs.json (sidecar; gitignored). The script re-renders
      `terraform.tfvars.json` from this sidecar on every run, which is the
      file Terraform actually consumes. Hand-edits to `terraform.tfvars.json`
      are lost on the next run -- always edit the JSON sidecar (or re-run
      the wizard) instead. The sidecar is also what destroy mode reads to
      know which resources to clean up.

    Resumability:
      Each input group is persisted to JSON atomically the moment it is
      collected; Ctrl-C never loses more than one group of progress. Re-runs
      replay the wizard with current values shown as defaults; press Enter
      to keep them. Terraform handles its own state, so re-running after a
      failed apply continues from where Terraform left off.

.PARAMETER Phase
    Bootstrap-mode phase(s) to run. Default 'all'. Ignored in -Destroy mode
    (destroy always runs preflight -> discover -> destroy in one shot).

.PARAMETER Engine
    Starter engine to package into the generated vending repository. Terraform
    is the default starter. Bicep is also available.

.PARAMETER Destroy
    Switch to destroy/teardown mode. Reverses what the bootstrap created.
    See DESCRIPTION for the two paths and safety rails.

.PARAMETER IncludeStateContainer
    Destroy mode only. Opt-in to deleting the Terraform state container.
    Refused even with this flag if the container has any blobs (would
    orphan vended-sub state).

.PARAMETER IncludeGitHubRepo
    Destroy mode only. Opt-in to deleting the entire GitHub repository
    (the seeded skeleton + every PR / issue / history).

.PARAMETER CleanBootstrapFolder
    Wipe local Terraform state + the wizard's sidecar files at the end of
    the run. Removes: `.terraform/`, `.terraform.lock.hcl`,
    `terraform.tfstate`, `terraform.tfstate.backup`, `tfplan`,
    `.bootstrap-inputs.json`, `.bootstrap-inputs.json.bak`,
    `terraform.tfvars.json`. Useful after `-Destroy` to fully reset, or
    standalone (no `-Destroy`, no bootstrap action) to scrub local files.

.PARAMETER NonInteractive
    Disable prompts. In bootstrap mode any required value missing from
    the sidecar causes failure; apply still requires -AutoApprove. In
    destroy mode every destructive op refuses without -AutoApprove.

.PARAMETER AutoApprove
    Bootstrap mode: skip the terraform apply prompt. Destroy mode: skip
    per-item Y/N confirmations. Tenant-mismatch refusal still applies.

.PARAMETER PlanOnly
    Bootstrap mode only. Run preflight + configure + validate + init +
    plan, then exit. Useful in CI for dry-run gating. (Use -WhatIf in
    destroy mode for the equivalent.)

.PARAMETER Reconfigure
    Bootstrap mode only. Pass -reconfigure to `terraform init`. Use after
    changing backend config or storage account.

.PARAMETER SkipPreflight
    Bypass tool-version and authentication checks. Escape hatch for
    environments where the wizard's checks return false negatives.

.PARAMETER InputsPath
    JSON sidecar path. Default: <script-dir>/.bootstrap-inputs.json

.PARAMETER TfvarsPath
    Rendered tfvars path. Default: <script-dir>/terraform.tfvars.json

.PARAMETER StarterRoot
    Directory containing starter-contract.json and the engine manifests.
    Defaults to the repository's starters directory.

.PARAMETER ScriptRoot
    Bootstrap module directory. Defaults to the script's own folder. Only
    override for unusual layouts.

.EXAMPLE
    pwsh ./Invoke-Bootstrap.ps1 -Engine Terraform
    Run the full wizard interactively (bootstrap mode).

.EXAMPLE
    pwsh ./Invoke-Bootstrap.ps1 -Phase configure
    Re-collect inputs without running terraform.

.EXAMPLE
    pwsh ./Invoke-Bootstrap.ps1 -Phase terraform -AutoApprove
    Skip wizard, run init/plan/apply non-interactively against the
    existing JSON sidecar.

.EXAMPLE
    pwsh ./Invoke-Bootstrap.ps1 -PlanOnly
    Dry-run end to end -- no apply.

.EXAMPLE
    pwsh ./Invoke-Bootstrap.ps1 -Destroy -WhatIf
    DESTROY MODE dry-run. Discovers what exists in Azure + GitHub that
    matches the sidecar; prints what would be deleted without doing it.

.EXAMPLE
    pwsh ./Invoke-Bootstrap.ps1 -Destroy
    Interactive teardown. Y/N for each delete. State container + GitHub
    repo are skipped (no opt-in flags).

.EXAMPLE
    pwsh ./Invoke-Bootstrap.ps1 -Destroy `
        -IncludeStateContainer -IncludeGitHubRepo `
        -CleanBootstrapFolder -AutoApprove
    Full nuclear cleanup: nuke UAMI + all RBAC + (empty) state container
    + GitHub repo + local files. Refuses if container has blobs or
    az tenant doesn't match.

.EXAMPLE
    pwsh ./Invoke-Bootstrap.ps1 -CleanBootstrapFolder
    Standalone local cleanup: wipe `.terraform/`, `tfstate*`, sidecar,
    rendered tfvars. No Azure / GitHub action.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Terraform', 'Bicep')]
    [string] $Engine = 'Terraform',

    [ValidateSet('preflight', 'configure', 'validate', 'terraform', 'all')]
    [string] $Phase = 'all',

    # Mode switches
    [switch] $Destroy,
    [switch] $CleanBootstrapFolder,

    # Destroy-mode opt-ins (DANGEROUS)
    [switch] $IncludeStateContainer,
    [switch] $IncludeGitHubRepo,

    # Shared behavior
    [switch] $NonInteractive,
    [switch] $AutoApprove,
    [switch] $SkipPreflight,

    # Bootstrap-mode only
    [switch] $PlanOnly,
    [switch] $Reconfigure,

    [string] $InputsPath,
    [string] $TfvarsPath,
    [string] $StarterRoot,
    [string] $ScriptRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

if (-not $InputsPath) { $InputsPath = Join-Path $ScriptRoot '.bootstrap-inputs.json' }
if (-not $TfvarsPath) { $TfvarsPath = Join-Path $ScriptRoot 'terraform.tfvars.json' }
if (-not $StarterRoot) { $StarterRoot = Join-Path (Split-Path -Parent $ScriptRoot) 'starters' }

$starterName = $Engine.ToLowerInvariant()
$starterManifestPath = Join-Path $StarterRoot "$starterName/starter.json"
if (-not (Test-Path -LiteralPath $starterManifestPath -PathType Leaf)) {
    throw "Starter manifest not found at '$starterManifestPath'."
}
$starterManifest = Get-Content -LiteralPath $starterManifestPath -Raw | ConvertFrom-Json

# Mutually-exclusive flag validation
if ($IncludeStateContainer -and -not $Destroy) {
    throw '-IncludeStateContainer requires -Destroy.'
}
if ($IncludeGitHubRepo -and -not $Destroy) {
    throw '-IncludeGitHubRepo requires -Destroy.'
}
if ($Destroy -and $PlanOnly) {
    throw '-Destroy and -PlanOnly are mutually exclusive. Use -Destroy -WhatIf for a destroy dry-run.'
}
if ($WhatIfPreference -and -not $Destroy -and -not $CleanBootstrapFolder) {
    throw '-WhatIf is supported only for destroy or local cleanup. Use -PlanOnly to preview bootstrap changes.'
}


# =============================================================================
# Section 0 -- Output helpers
# =============================================================================

function Write-Banner {
    param([string] $Text)
    $line = '=' * ($Text.Length + 4)
    Write-Host ''
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Text  " -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
}

function Write-Header {
    param([string] $Text)
    Write-Host ''
    Write-Host "── $Text " -ForegroundColor Cyan
    Write-Host ('─' * 78) -ForegroundColor DarkGray
}

function Write-Ok {
    param([string] $Text)
    Write-Host "  ✓ $Text" -ForegroundColor Green
}

function Write-Fail {
    param([string] $Text)
    Write-Host "  ✗ $Text" -ForegroundColor Red
}

function Write-Warn {
    param([string] $Text)
    Write-Host "  ! $Text" -ForegroundColor Yellow
}

function Write-Info {
    param([string] $Text)
    Write-Host "  · $Text" -ForegroundColor DarkGray
}

# Destroy-mode helpers (line-level icons distinct from bootstrap-mode):
function Write-Plan  { param([string] $Text) Write-Host "  → $Text" -ForegroundColor Cyan }
function Write-Done  { param([string] $Text) Write-Host "  ✗ DELETED  $Text" -ForegroundColor DarkYellow }
function Write-Skip  { param([string] $Text) Write-Host "  - skipped: $Text" -ForegroundColor DarkGray }


# =============================================================================
# Section 1 -- Validation primitives
# =============================================================================

function Test-Guid {
    param([string] $Value)
    return $Value -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
}

function Test-MgResourceId {
    param([string] $Value)
    return $Value -match '^/providers/Microsoft\.Management/managementGroups/[A-Za-z0-9._\-()]+$'
}

function Test-MgBareName {
    param([string] $Value)
    # Bare name -- NOT a resource ID
    return ($Value -match '^[A-Za-z0-9._\-()]+$') -and ($Value -notmatch '^/providers/')
}

function Test-AzureLocation {
    param([string] $Value)
    return $Value -match '^[a-z][a-z0-9]+$'
}

function Test-ResourceName {
    param([string] $Value, [int] $MinLength = 1, [int] $MaxLength = 90)
    if ($Value.Length -lt $MinLength -or $Value.Length -gt $MaxLength) { return $false }
    return $Value -match '^[A-Za-z0-9][A-Za-z0-9._\-]*$'
}

function Test-StorageAccountName {
    param([string] $Value)
    return $Value -match '^[a-z0-9]{3,24}$'
}

function Test-GitHubHandle {
    param([string] $Value)
    return $Value -match '^@[A-Za-z0-9_][A-Za-z0-9_-]*(/[A-Za-z0-9_][A-Za-z0-9_-]*)?$'
}

function Test-GitHubOrgOrUser {
    param([string] $Value)
    return $Value -match '^[A-Za-z0-9_][A-Za-z0-9_-]{0,38}$'
}


# =============================================================================
# Section 2 -- Prompt helpers
# =============================================================================

function Read-PromptString {
    param(
        [string] $Label,
        [string] $Default,
        [string] $HelpText,
        [scriptblock] $Validator,
        [string] $ValidationMessage,
        [switch] $AllowEmpty
    )
    while ($true) {
        if ($HelpText) {
            Write-Host ''
            Write-Host "    $HelpText" -ForegroundColor DarkGray
        }
        $promptText = "    $Label"
        if ($PSBoundParameters.ContainsKey('Default') -and $Default -ne '') {
            $promptText += " [$Default]"
        }
        elseif ($AllowEmpty) {
            $promptText += " [empty]"
        }
        $promptText += ': '
        $raw = Read-Host -Prompt $promptText
        if ($raw -eq '' -and $PSBoundParameters.ContainsKey('Default')) { $raw = $Default }
        if ($raw -eq '' -and $AllowEmpty) { return '' }
        if ($raw -eq '') {
            Write-Fail "Value is required."
            continue
        }
        if ($Validator) {
            $ok = & $Validator $raw
            if (-not $ok) {
                Write-Fail ($ValidationMessage ?? 'Invalid value.')
                continue
            }
        }
        return $raw
    }
}

function Read-PromptChoice {
    param(
        [string] $Label,
        [string[]] $Choices,
        [string] $Default,
        [string] $HelpText
    )
    while ($true) {
        if ($HelpText) {
            Write-Host ''
            Write-Host "    $HelpText" -ForegroundColor DarkGray
        }
        $shown = $Choices -join ' / '
        $prompt = "    $Label ($shown)"
        if ($Default) { $prompt += " [$Default]" }
        $prompt += ': '
        $raw = (Read-Host -Prompt $prompt).Trim()
        if ($raw -eq '' -and $Default) { $raw = $Default }
        foreach ($c in $Choices) {
            if ($raw -ieq $c) { return $c }
        }
        Write-Fail "Choose one of: $shown"
    }
}

function Read-PromptBool {
    param(
        [string] $Label,
        [bool] $Default,
        [string] $HelpText
    )
    $defaultStr = if ($Default) { 'Y' } else { 'N' }
    while ($true) {
        if ($HelpText) {
            Write-Host ''
            Write-Host "    $HelpText" -ForegroundColor DarkGray
        }
        $raw = (Read-Host -Prompt "    $Label [Y/n if default=Y, y/N if default=N -- default=$defaultStr]").Trim()
        if ($raw -eq '') { return $Default }
        if ($raw -match '^(y|yes|true|1)$') { return $true }
        if ($raw -match '^(n|no|false|0)$') { return $false }
        Write-Fail "Answer y or n."
    }
}


# =============================================================================
# Section 3 -- JSON state I/O (atomic write + .bak rotation)
# =============================================================================

function Get-Inputs {
    param([string] $Path)
    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return @{}
    }
    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        # PowerShell returns an OrderedHashtable here. Copy into a regular
        # Hashtable so mutations survive [hashtable] parameter binding.
        $parsed = ConvertFrom-Json -InputObject $raw -AsHashtable -Depth 32
        return @{} + $parsed
    }
    catch {
        Write-Fail "Failed to parse inputs file: $Path"
        Write-Fail "  $($_.Exception.Message)"
        $bak = "$Path.bak"
        if (Test-Path $bak) {
            $answer = Read-Host "  Restore from backup ($bak)? [Y/n]"
            if ($answer -notmatch '^(n|no)$') {
                Copy-Item -Path $bak -Destination $Path -Force
                return Get-Inputs -Path $Path
            }
        }
        throw "Cannot continue with corrupt inputs file."
    }
}

function Save-Inputs {
    param(
        [string] $Path,
        $Inputs
    )
    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ConvertTo-Json -InputObject $Inputs -Depth 32
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))

    # Validate the temp file actually parses before swapping in.
    try {
        $null = ConvertFrom-Json -InputObject (Get-Content -Path $tmp -Raw) -AsHashtable -Depth 32
    }
    catch {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
        throw "Refusing to save: validation of serialized JSON failed. $($_.Exception.Message)"
    }

    if (Test-Path -Path $Path) {
        Copy-Item -Path $Path -Destination "$Path.bak" -Force
    }
    Move-Item -Path $tmp -Destination $Path -Force
}


# =============================================================================
# Section 4 -- Preflight phase
# =============================================================================

function Test-ToolVersion {
    param(
        [string] $Tool,
        [string] $VersionArg = '--version',
        [scriptblock] $VersionExtractor,
        [version] $MinVersion,
        [version] $MaxVersionExclusive
    )
    $cmd = Get-Command -Name $Tool -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Fail "$Tool not found on PATH."
        return $false
    }
    try {
        $output = & $Tool $VersionArg 2>&1 | Out-String
    }
    catch {
        Write-Fail "$Tool failed to run: $($_.Exception.Message)"
        return $false
    }
    $extracted = & $VersionExtractor $output
    if (-not $extracted) {
        Write-Warn "$Tool present but couldn't parse version from output. Skipping version gate."
        return $true
    }
    if ($extracted -lt $MinVersion) {
        Write-Fail "$Tool version $extracted is older than required $MinVersion."
        return $false
    }
    if ($MaxVersionExclusive -and $extracted -ge $MaxVersionExclusive) {
        Write-Fail "$Tool version $extracted is outside the supported range >= $MinVersion and < $MaxVersionExclusive."
        return $false
    }
    $supportedRange = if ($MaxVersionExclusive) {
        ">= $MinVersion and < $MaxVersionExclusive"
    }
    else {
        ">= $MinVersion"
    }
    Write-Ok "$Tool $extracted ($supportedRange)"
    return $true
}

function Invoke-Preflight {
    param([hashtable] $Inputs)

    Write-Header 'Preflight: required tools + auth'

    $ok = $true

    $ok = (Test-ToolVersion -Tool 'terraform' `
            -VersionArg 'version' `
            -MinVersion '1.10.0' `
            -MaxVersionExclusive '2.0.0' `
            -VersionExtractor {
            param($out)
            if ($out -match 'Terraform v?(\d+\.\d+\.\d+)') { return [version] $Matches[1] }
        }) -and $ok

    $ok = (Test-ToolVersion -Tool 'az' `
            -VersionArg '--version' `
            -MinVersion '2.64.0' `
            -VersionExtractor {
            param($out)
            if ($out -match 'azure-cli\s+(\d+\.\d+\.\d+)') { return [version] $Matches[1] }
        }) -and $ok

    $ok = (Test-ToolVersion -Tool 'gh' `
            -VersionArg '--version' `
            -MinVersion '2.50.0' `
            -VersionExtractor {
            param($out)
            if ($out -match 'gh version (\d+\.\d+\.\d+)') { return [version] $Matches[1] }
        }) -and $ok

    # Resolve GitHub token (prefer env var; fall back to `gh auth token`).
    $tokenSource = $null
    $token = $env:GITHUB_TOKEN
    if ($token) {
        $tokenSource = '$env:GITHUB_TOKEN'
    }
    else {
        try {
            $token = (& gh auth token 2>$null).Trim()
            if ($token) { $tokenSource = '`gh auth token`' }
        }
        catch { }
    }

    if (-not $token) {
        Write-Fail 'No GitHub token available. Set $env:GITHUB_TOKEN or run `gh auth login`.'
        $ok = $false
    }
    else {
        Write-Ok "GitHub token resolved from $tokenSource."
        $env:GITHUB_TOKEN = $token  # process-scoped; never persisted

        # Probe scopes via API. Classic PATs return X-OAuth-Scopes; fine-grained
        # PATs do not -- in that case we can only verify the call succeeded.
        try {
            $resp = Invoke-WebRequest `
                -Uri 'https://api.github.com/user' `
                -Headers @{
                Authorization          = "token $token"
                'X-GitHub-Api-Version' = '2022-11-28'
                Accept                 = 'application/vnd.github+json'
            } -UseBasicParsing -ErrorAction Stop
            $scopesHeader = $resp.Headers['X-OAuth-Scopes']
            if ($scopesHeader) {
                $scopes = @(($scopesHeader -join ',') -split ',' | ForEach-Object { $_.Trim() })
                Write-Ok "Token scopes: $($scopes -join ', ')"
                $needed = @('workflow', 'repo')
                foreach ($n in $needed) {
                    if ($scopes -notcontains $n -and ($scopes -notcontains 'repo' -and $n -eq 'repo')) {
                        Write-Warn "Token is missing recommended scope: $n"
                    }
                }
            }
            else {
                Write-Info 'Token did not return X-OAuth-Scopes (likely a fine-grained PAT). Scope check skipped.'
            }
        }
        catch {
            Write-Fail "GitHub /user probe failed: $($_.Exception.Message)"
            $ok = $false
        }
    }

    # Azure CLI session
    try {
        $azAccount = (& az account show 2>$null) | ConvertFrom-Json
        if (-not $azAccount) { throw 'no active az session' }
        Write-Ok "Az CLI session: $($azAccount.user.name) @ $($azAccount.tenantId) (sub: $($azAccount.id))"
        if ($Inputs.tenant_id -and $Inputs.tenant_id -ne $azAccount.tenantId) {
            Write-Warn "JSON tenant_id ($($Inputs.tenant_id)) does not match az session tenant ($($azAccount.tenantId)). Will switch before terraform runs."
        }
    }
    catch {
        Write-Fail "Az CLI not signed in ($($_.Exception.Message)). Run ``az login --tenant <tenant-id>``."
        $ok = $false
    }

    if (-not $ok) {
        throw 'Preflight failed. Resolve the items above (or re-run with -SkipPreflight) and try again.'
    }

    Write-Host ''
    Write-Ok 'Preflight complete.'
}


# =============================================================================
# Section 5 -- Configure phase
# =============================================================================

function Edit-Group {
    <#
    Group-level keep/edit prompt. Returns $true if the operator wants to
    re-prompt the group, $false to keep current values.
    #>
    param(
        [string] $Title,
        [string[]] $SummaryLines
    )
    Write-Header "Configure: $Title"
    if ($SummaryLines -and $SummaryLines.Count -gt 0) {
        foreach ($line in $SummaryLines) { Write-Host "    $line" -ForegroundColor DarkGray }
        Write-Host ''
        $choice = (Read-Host '    Keep this group as-is? [Y/edit]').Trim().ToLower()
        return ($choice -eq 'edit' -or $choice -eq 'e')
    }
    return $true
}

function Get-OrSet {
    <#
    Helper: if the inputs hashtable already has the key, return it (used
    as default). Otherwise prompt and persist.
    #>
    param(
        [hashtable] $Inputs,
        [string] $Key,
        [scriptblock] $PromptScript
    )
    if ($Inputs.Contains($Key) -and $null -ne $Inputs[$Key] -and $Inputs[$Key] -ne '') {
        return $Inputs[$Key]
    }
    return & $PromptScript
}

function Configure-IdentityLocation {
    param([hashtable] $Inputs)

    $summary = @()
    if ($Inputs.tenant_id) { $summary += "tenant_id                 = $($Inputs.tenant_id)" }
    if ($Inputs.platform_subscription_id) { $summary += "platform_subscription_id  = $($Inputs.platform_subscription_id)" }
    if ($Inputs.location) { $summary += "location                  = $($Inputs.location)" }
    if ($Inputs.uami_resource_group_name) { $summary += "uami_resource_group_name  = $($Inputs.uami_resource_group_name)" }
    if ($Inputs.uami_name) { $summary += "uami_name                 = $($Inputs.uami_name)" }

    if (-not (Edit-Group -Title 'Identity & location' -SummaryLines $summary)) { return }

    $Inputs.tenant_id = Read-PromptString `
        -Label 'tenant_id' `
        -Default ($Inputs.tenant_id ?? '') `
        -HelpText 'Microsoft Entra tenant ID (GUID).' `
        -Validator { param($v) Test-Guid $v } `
        -ValidationMessage 'Must be a GUID.'

    $Inputs.platform_subscription_id = Read-PromptString `
        -Label 'platform_subscription_id' `
        -Default ($Inputs.platform_subscription_id ?? '') `
        -HelpText 'Subscription that owns the pipeline UAMI and the Terraform state SA (GUID).' `
        -Validator { param($v) Test-Guid $v } `
        -ValidationMessage 'Must be a GUID.'

    $Inputs.location = Read-PromptString `
        -Label 'location' `
        -Default ($Inputs.location ?? 'westeurope') `
        -HelpText 'Azure region for the UAMI (e.g. westeurope, norwayeast).' `
        -Validator { param($v) Test-AzureLocation $v } `
        -ValidationMessage 'Use the short region code (lowercase letters/numbers, no spaces).'

    $Inputs.uami_resource_group_name = Read-PromptString `
        -Label 'uami_resource_group_name' `
        -Default ($Inputs.uami_resource_group_name ?? 'rg-platform-identity-prod') `
        -HelpText 'Existing resource group that will hold the pipeline UAMI.' `
        -Validator { param($v) Test-ResourceName $v -MinLength 1 -MaxLength 90 } `
        -ValidationMessage 'Invalid resource group name.'

    $Inputs.uami_name = Read-PromptString `
        -Label 'uami_name' `
        -Default ($Inputs.uami_name ?? 'id-subvending-pipeline') `
        -HelpText 'Name of the User-Assigned Managed Identity.' `
        -Validator { param($v) Test-ResourceName $v -MinLength 3 -MaxLength 128 } `
        -ValidationMessage 'Invalid managed-identity name.'
}

function Configure-State {
    param([hashtable] $Inputs)

    $summary = @()
    if ($Inputs.state_storage_account_resource_group_name) { $summary += "state RG        = $($Inputs.state_storage_account_resource_group_name)" }
    if ($Inputs.state_storage_account_name) { $summary += "state SA        = $($Inputs.state_storage_account_name)" }
    if ($Inputs.state_container_name) { $summary += "state container = $($Inputs.state_container_name)" }

    if (-not (Edit-Group -Title 'Terraform state backend' -SummaryLines $summary)) { return }

    $Inputs.state_storage_account_resource_group_name = Read-PromptString `
        -Label 'state_storage_account_resource_group_name' `
        -Default ($Inputs.state_storage_account_resource_group_name ?? 'rg-platform-tfstate-prod') `
        -HelpText 'Resource group of the existing platform Terraform state storage account.' `
        -Validator { param($v) Test-ResourceName $v }

    $Inputs.state_storage_account_name = Read-PromptString `
        -Label 'state_storage_account_name' `
        -Default ($Inputs.state_storage_account_name ?? 'stplatformtfstate') `
        -HelpText 'Existing platform storage account name (3-24 chars, lowercase + digits).' `
        -Validator { param($v) Test-StorageAccountName $v } `
        -ValidationMessage 'Storage account names: 3-24 chars, lowercase letters and digits only.'

    $Inputs.state_container_name = Read-PromptString `
        -Label 'state_container_name' `
        -Default ($Inputs.state_container_name ?? 'subvending-tfstate') `
        -HelpText 'New container the bootstrap creates inside that SA for sub-vending state.' `
        -Validator { param($v) $v -match '^[a-z0-9](?!.*--)[a-z0-9-]{1,61}[a-z0-9]$' } `
        -ValidationMessage 'Container name: 3-63 chars, lowercase, no consecutive hyphens.'
}

function Configure-Rbac {
    param([hashtable] $Inputs)

    $summary = @()
    if ($Inputs.alz_root_management_group_id) { $summary += "alz_root_management_group_id    = $($Inputs.alz_root_management_group_id)" }
    if ($Inputs.connectivity_subscription_id) { $summary += "connectivity_subscription_id    = $($Inputs.connectivity_subscription_id)" }
    if ($Inputs.Contains('grant_user_access_administrator')) { $summary += "grant_user_access_administrator = $($Inputs.grant_user_access_administrator)" }

    if (-not (Edit-Group -Title 'Azure RBAC scopes' -SummaryLines $summary)) { return }

    $Inputs.alz_root_management_group_id = Read-PromptString `
        -Label 'alz_root_management_group_id' `
        -Default ($Inputs.alz_root_management_group_id ?? '') `
        -HelpText 'Bare management-group NAME (NOT a full resource ID). Must be a parent of every archetype MG below.' `
        -Validator { param($v) Test-MgBareName $v } `
        -ValidationMessage 'Use the bare MG name (no /providers/...).'

    $Inputs.connectivity_subscription_id = Read-PromptString `
        -Label 'connectivity_subscription_id' `
        -Default ($Inputs.connectivity_subscription_id ?? '') `
        -HelpText 'Connectivity (hub) subscription ID. Used to scope Network Contributor for hub VNet peering.' `
        -Validator { param($v) Test-Guid $v } `
        -ValidationMessage 'Must be a GUID.'

    $currentUAA = if ($Inputs.Contains('grant_user_access_administrator')) { [bool] $Inputs.grant_user_access_administrator } else { $true }
    $Inputs.grant_user_access_administrator = Read-PromptBool `
        -Label 'grant_user_access_administrator' `
        -Default $currentUAA `
        -HelpText 'Grant User Access Administrator at the root MG scope. Required when sub YAML files declare roleAssignments.'
}

function Configure-GitHubRepo {
    param([hashtable] $Inputs)

    $summary = @()
    if ($Inputs.github_owner) { $summary += "github_owner                 = $($Inputs.github_owner)" }
    if ($Inputs.github_repository_name) { $summary += "github_repository_name       = $($Inputs.github_repository_name)" }
    if ($Inputs.Contains('create_github_repository')) { $summary += "create_github_repository     = $($Inputs.create_github_repository)" }
    if ($Inputs.github_repository_visibility) { $summary += "github_repository_visibility = $($Inputs.github_repository_visibility)" }
    if ($Inputs.github_default_branch) { $summary += "github_default_branch        = $($Inputs.github_default_branch)" }
    if ($Inputs.github_oidc_subject_mode) { $summary += "github_oidc_subject_mode    = $($Inputs.github_oidc_subject_mode)" }
    if ($Inputs.github_owner_id) { $summary += "github_owner_id             = $($Inputs.github_owner_id)" }

    if (-not (Edit-Group -Title 'GitHub repository' -SummaryLines $summary)) { return }

    $Inputs.github_owner = Read-PromptString `
        -Label 'github_owner' `
        -Default ($Inputs.github_owner ?? '') `
        -HelpText 'GitHub org or user that owns (or will own) the seeded vending repo.' `
        -Validator { param($v) Test-GitHubOrgOrUser $v } `
        -ValidationMessage 'Use the bare org/user login (e.g. "contoso").'

    $Inputs.github_repository_name = Read-PromptString `
        -Label 'github_repository_name' `
        -Default ($Inputs.github_repository_name ?? 'sub-vending') `
        -HelpText 'Repository name.' `
        -Validator { param($v) $v -match '^[A-Za-z0-9._\-]{1,100}$' }

    $currentCreate = if ($Inputs.Contains('create_github_repository')) { [bool] $Inputs.create_github_repository } else { $false }
    $Inputs.create_github_repository = Read-PromptBool `
        -Label 'create_github_repository' `
        -Default $currentCreate `
        -HelpText 'Create the repo from this script (true) or expect it to already exist (false).'

    $Inputs.github_repository_visibility = Read-PromptChoice `
        -Label 'github_repository_visibility' `
        -Choices @('private', 'internal', 'public') `
        -Default ($Inputs.github_repository_visibility ?? 'private') `
        -HelpText 'Visibility -- only used when create_github_repository=true.'

    $Inputs.github_default_branch = Read-PromptString `
        -Label 'github_default_branch' `
        -Default ($Inputs.github_default_branch ?? 'main') `
        -HelpText 'Default branch -- used in OIDC subject claims.' `
        -Validator { param($v) $v -match '^[A-Za-z0-9._\-/]+$' }

    $Inputs.github_oidc_subject_mode = Read-PromptChoice `
        -Label 'github_oidc_subject_mode' `
        -Choices @('standard', 'immutable') `
        -Default ($Inputs.github_oidc_subject_mode ?? 'standard') `
        -HelpText 'Use immutable when the GitHub owner includes numeric owner/repository IDs in OIDC subjects.'

    if ($Inputs.github_oidc_subject_mode -eq 'immutable') {
        $owner = (Invoke-GhApi -Method 'GET' -Path "/users/$($Inputs.github_owner)") | ConvertFrom-Json
        if (-not $owner.id) {
            throw "Could not resolve the numeric GitHub owner ID for '$($Inputs.github_owner)'."
        }
        $Inputs.github_owner_id = [long] $owner.id
        Write-Ok "Resolved GitHub owner ID $($Inputs.github_owner_id)."
    }
    else {
        $Inputs.Remove('github_owner_id')
    }
}

function Configure-BranchProtection {
    param([hashtable] $Inputs)

    $summary = @()
    if ($Inputs.Contains('enforce_branch_protection')) { $summary += "enforce_branch_protection                         = $($Inputs.enforce_branch_protection)" }
    if ($Inputs.Contains('branch_protection_required_approving_review_count')) { $summary += "branch_protection_required_approving_review_count = $($Inputs.branch_protection_required_approving_review_count)" }
    if ($Inputs.branch_protection_required_status_checks) {
        $summary += "branch_protection_required_status_checks          = $($Inputs.branch_protection_required_status_checks -join ', ')"
    }

    if (-not (Edit-Group -Title 'Branch protection on default branch' -SummaryLines $summary)) { return }

    $currentEnforce = if ($Inputs.Contains('enforce_branch_protection')) { [bool] $Inputs.enforce_branch_protection } else { $true }
    $Inputs.enforce_branch_protection = Read-PromptBool `
        -Label 'enforce_branch_protection' `
        -Default $currentEnforce `
        -HelpText 'If true, requires PR + status checks before merge to the default branch.'

    if ($Inputs.enforce_branch_protection) {
        $currentRevs = if ($Inputs.Contains('branch_protection_required_approving_review_count')) { [int] $Inputs.branch_protection_required_approving_review_count } else { 1 }
        $revs = Read-PromptString `
            -Label 'branch_protection_required_approving_review_count' `
            -Default "$currentRevs" `
            -HelpText 'Approving reviews required before merge.' `
            -Validator { param($v) ($v -as [int]) -ne $null -and ([int]$v) -ge 0 -and ([int]$v) -le 6 } `
            -ValidationMessage 'Enter an integer 0-6.'
        $Inputs.branch_protection_required_approving_review_count = [int] $revs

        $checksDefault = if ($Inputs.branch_protection_required_status_checks) { $Inputs.branch_protection_required_status_checks } else {
            @('PR Validate / YAML schema validation', 'PR Validate / PR Validate Result')
        }
        Write-Host ''
        Write-Host "    branch_protection_required_status_checks defaults to:" -ForegroundColor DarkGray
        $checksDefault | ForEach-Object { Write-Host "        - $_" -ForegroundColor DarkGray }
        $custom = Read-PromptBool `
            -Label 'Customize required status checks?' `
            -Default $false `
            -HelpText 'Defaults match the shipped pr-validate.yml job names. Only customize if you renamed jobs.'
        if ($custom) {
            $list = [System.Collections.Generic.List[string]]::new()
            Write-Host "    Enter check names one per line. Empty line to finish." -ForegroundColor DarkGray
            while ($true) {
                $line = (Read-Host '      check name').Trim()
                if ($line -eq '') { break }
                $list.Add($line)
            }
            $Inputs.branch_protection_required_status_checks = $list.ToArray()
        }
        else {
            $Inputs.branch_protection_required_status_checks = $checksDefault
        }
    }
}

function Configure-ProductionEnv {
    param([hashtable] $Inputs)

    $summary = @()
    if ($Inputs.production_environment_name) { $summary += "production_environment_name  = $($Inputs.production_environment_name)" }
    $userCount = if ($Inputs.production_reviewer_user_ids) { $Inputs.production_reviewer_user_ids.Count } else { 0 }
    $teamCount = if ($Inputs.production_reviewer_team_ids) { $Inputs.production_reviewer_team_ids.Count } else { 0 }
    $summary += "production_reviewer_user_ids = $userCount entries"
    $summary += "production_reviewer_team_ids = $teamCount entries"

    if (-not (Edit-Group -Title 'Production environment approvers' -SummaryLines $summary)) { return }

    $Inputs.production_environment_name = Read-PromptString `
        -Label 'production_environment_name' `
        -Default ($Inputs.production_environment_name ?? 'production') `
        -HelpText 'Name of the GitHub Environment that gates apply.'

    Write-Host ''
    Write-Host '    Reviewers: enter GitHub usernames or org/team slugs. The wizard will' -ForegroundColor DarkGray
    Write-Host '    look up numeric IDs via the GitHub API. Empty line to finish each list.' -ForegroundColor DarkGray
    Write-Host '    Leave both empty if you will configure approvers later in the UI.' -ForegroundColor DarkGray
    Write-Host ''

    $Inputs.production_reviewer_user_ids = @(Get-GitHubNumericIds -Kind 'user' -Existing $Inputs.production_reviewer_user_ids)
    $Inputs.production_reviewer_team_ids = @(Get-GitHubNumericIds -Kind 'team' -Existing $Inputs.production_reviewer_team_ids)
    Write-ProductionReviewerGuardrail -Inputs $Inputs
}

function Get-GitHubNumericIds {
    param(
        [ValidateSet('user', 'team')] [string] $Kind,
        [array] $Existing
    )
    $current = @($Existing) | Where-Object { $_ }
    if ($current.Count -gt 0) {
        Write-Host "    Current $Kind IDs: $($current -join ', ')" -ForegroundColor DarkGray
    }
    $keep = Read-PromptBool -Label "Keep current $Kind IDs?" -Default ($current.Count -gt 0) `
        -HelpText "Choose No to replace the list."
    if ($keep -and $current.Count -gt 0) { return $current }

    $ids = [System.Collections.Generic.List[long]]::new()
    while ($true) {
        if ($Kind -eq 'user') {
            $login = (Read-Host '      GitHub username (empty to finish)').Trim()
            if ($login -eq '') { break }
            try {
                $u = (& gh api "users/$login" 2>$null) | ConvertFrom-Json
                if ($u -and $u.id) {
                    Write-Ok "  $login → id=$($u.id)"
                    $ids.Add([long] $u.id)
                }
                else {
                    Write-Fail "  Could not resolve user '$login'."
                }
            }
            catch {
                Write-Fail "  Lookup failed: $($_.Exception.Message)"
            }
        }
        else {
            $slug = (Read-Host '      Team slug (org/team-slug; empty to finish)').Trim()
            if ($slug -eq '') { break }
            if ($slug -notmatch '^([^/]+)/([^/]+)$') { Write-Fail "  Expected org/team-slug."; continue }
            $org = $Matches[1]
            $team = $Matches[2]
            try {
                $t = (& gh api "orgs/$org/teams/$team" 2>$null) | ConvertFrom-Json
                if ($t -and $t.id) {
                    Write-Ok "  $slug → id=$($t.id)"
                    $ids.Add([long] $t.id)
                }
                else {
                    Write-Fail "  Could not resolve team '$slug'."
                }
            }
            catch {
                Write-Fail "  Lookup failed: $($_.Exception.Message)"
            }
        }
    }
    return $ids.ToArray()
}

function Get-ProductionReviewerAssessment {
    param([hashtable] $Inputs)

    $eligibleReviewerIds = [System.Collections.Generic.HashSet[long]]::new()
    foreach ($userId in @($Inputs.production_reviewer_user_ids)) {
        if ($userId) {
            $null = $eligibleReviewerIds.Add([long] $userId)
        }
    }

    $failedTeamIds = [System.Collections.Generic.List[long]]::new()
    foreach ($teamId in @($Inputs.production_reviewer_team_ids)) {
        if (-not $teamId) { continue }

        $memberIds = @(& gh api --paginate "teams/$teamId/members?per_page=100" --jq '.[].id' 2>$null)
        if ($LASTEXITCODE -ne 0) {
            $failedTeamIds.Add([long] $teamId)
            continue
        }

        foreach ($memberId in $memberIds) {
            $parsedId = 0L
            if ([long]::TryParse("$memberId", [ref] $parsedId)) {
                $null = $eligibleReviewerIds.Add($parsedId)
            }
        }
    }

    return [pscustomobject]@{
        EligibleReviewerCount = $eligibleReviewerIds.Count
        FailedTeamIds         = $failedTeamIds.ToArray()
        IsComplete            = $failedTeamIds.Count -eq 0
    }
}

function Write-ProductionReviewerGuardrail {
    param(
        [hashtable] $Inputs,
        [switch] $Validation
    )

    $assessment = Get-ProductionReviewerAssessment -Inputs $Inputs
    if (-not $assessment.IsComplete) {
        Write-Warn "Could not verify membership for production reviewer team ID(s): $($assessment.FailedTeamIds -join ', '). Ensure at least two eligible people can approve deployments when self-review prevention is enabled."
        return
    }

    if ($assessment.EligibleReviewerCount -eq 0) {
        Write-Warn 'No eligible production environment reviewers are configured. Configure reviewers in GitHub before using the repository for production deployments.'
        return
    }

    if ($assessment.EligibleReviewerCount -eq 1) {
        Write-Warn 'Only one eligible production environment reviewer was found while self-review prevention is enabled. If that person starts or merges a deployment-triggering change, they cannot approve it normally. One-person setups are allowed: a repository administrator can use "Start all waiting jobs" while the job is pending, or you can add a second eligible reviewer.'
        return
    }

    if ($Validation) {
        Write-Ok "Production environment has $($assessment.EligibleReviewerCount) eligible reviewers."
    }
}

function Configure-BillingScopes {
    param([hashtable] $Inputs)

    $current = $Inputs.billing_scopes
    $summary = @()
    if ($current -and $current.Keys.Count -gt 0) {
        foreach ($k in $current.Keys) {
            $type = $current[$k].agreement_type
            $summary += "billing_scopes[$k] = $type"
        }
    }
    else {
        $summary += '(none configured)'
    }

    if (-not (Edit-Group -Title 'Billing scopes' -SummaryLines $summary)) { return }

    Write-Host ''
    Write-Host '    Billing scopes are stored as a map; the `default` key is mandatory.' -ForegroundColor DarkGray
    Write-Host '    Per-sub YAMLs can opt into a non-default scope via `billingScopeKey:`.' -ForegroundColor DarkGray
    Write-Host '    See docs/billing-scopes.md for path formats and discovery commands.' -ForegroundColor DarkGray

    $scopes = [ordered]@{}
    $first = $true
    while ($true) {
        if ($first) {
            $key = 'default'
            Write-Host ''
            Write-Host "    Adding required scope: default" -ForegroundColor Cyan
            $first = $false
        }
        else {
            $more = Read-PromptBool -Label 'Add another billing scope?' -Default $false
            if (-not $more) { break }
            $key = Read-PromptString -Label 'scope key (e.g. sandbox, mca_prod)' `
                -Validator { param($v) ($v -match '^[a-z][a-z0-9_]{0,30}$') -and ($scopes.Keys -notcontains $v) } `
                -ValidationMessage 'Key must be lowercase alphanumeric+underscore, unique, and start with a letter.'
        }

        $type = Read-PromptChoice -Label 'agreement_type' -Choices @('EA', 'MCA', 'MPA') `
            -HelpText 'EA = Enterprise Agreement, MCA = Microsoft Customer Agreement, MPA = Microsoft Partner Agreement.'

        $scope = [ordered]@{ agreement_type = $type }
        switch ($type) {
            'EA' {
                $scope.ea = [ordered]@{
                    billing_account_name  = Read-PromptString -Label 'ea.billing_account_name' `
                        -HelpText 'Numeric EA billing account ID, e.g. 7690848.' `
                        -Validator { param($v) $v -match '^[0-9]+$' } `
                        -ValidationMessage 'Expect a numeric ID.'
                    enrollment_account_id = Read-PromptString -Label 'ea.enrollment_account_id' `
                        -HelpText 'Numeric EA enrollment account ID, e.g. 403507.' `
                        -Validator { param($v) $v -match '^[0-9]+$' } `
                        -ValidationMessage 'Expect a numeric ID.'
                }
            }
            'MCA' {
                $scope.mca = [ordered]@{
                    billing_account_name = Read-PromptString -Label 'mca.billing_account_name' `
                        -HelpText 'MCA billing account name (long composite ID, e.g. <guid>:<guid>_<date>).' `
                        -Validator { param($v) $v -match '^[0-9a-fA-F]{8}-.*:.*_\d{4}-\d{2}-\d{2}$' } `
                        -ValidationMessage 'Format: <guid>:<guid>_<YYYY-MM-DD>'
                    billing_profile_name = Read-PromptString -Label 'mca.billing_profile_name' `
                        -HelpText 'MCA billing profile name (e.g. ABCD-EFGH-IJK-LMN).'
                    invoice_section_name = Read-PromptString -Label 'mca.invoice_section_name' `
                        -HelpText 'MCA invoice section name (e.g. WXYZ-1234).'
                }
            }
            'MPA' {
                $scope.mpa = [ordered]@{
                    billing_account_name = Read-PromptString -Label 'mpa.billing_account_name' `
                        -HelpText 'MPA billing account name (similar composite to MCA).'
                    customer_id          = Read-PromptString -Label 'mpa.customer_id' `
                        -HelpText 'Customer GUID under the MPA.' `
                        -Validator { param($v) Test-Guid $v } `
                        -ValidationMessage 'Must be a GUID.'
                }
            }
        }

        $scopes[$key] = $scope
        Write-Ok "Recorded billing_scopes[$key] ($type)."

        # Persist this single scope progressively in case Ctrl-C lands
        # between two scopes -- replace the whole map each pass.
        $Inputs.billing_scopes = $scopes
        Save-Inputs -Path $InputsPath -Inputs $Inputs
    }

    if (-not $scopes.Contains('default')) {
        throw 'billing_scopes must contain a "default" entry. Re-run configure.'
    }
}

function Configure-ManagementGroups {
    param([hashtable] $Inputs)

    $current = $Inputs.management_group_ids
    $summary = @()
    if ($current -and $current.Keys.Count -gt 0) {
        foreach ($k in $current.Keys) { $summary += "$k = $($current[$k])" }
    }
    else {
        $summary += '(none configured)'
    }
    if (-not (Edit-Group -Title 'Management group IDs (archetype → MG)' -SummaryLines $summary)) { return }

    Write-Host ''
    Write-Host '    Keys MUST match archetype values in landingzones/<archetype>/*.yaml' -ForegroundColor DarkGray
    Write-Host '    (corp / online / sandbox by default). Values are FULL resource IDs.' -ForegroundColor DarkGray

    $mgs = [ordered]@{}
    $defaults = @('corp', 'online', 'sandbox')
    foreach ($arch in $defaults) {
        $existing = if ($current) { $current[$arch] } else { '' }
        $id = Read-PromptString -Label "$arch -> MG resource ID" `
            -Default ($existing ?? '') `
            -Validator { param($v) Test-MgResourceId $v } `
            -ValidationMessage 'Format: /providers/Microsoft.Management/managementGroups/<name>'
        $mgs[$arch] = $id
    }
    while ($true) {
        $more = Read-PromptBool -Label 'Add another archetype?' -Default $false
        if (-not $more) { break }
        $arch = Read-PromptString -Label 'archetype name' `
            -Validator { param($v) ($v -match '^[a-z][a-z0-9_-]{0,30}$') -and ($mgs.Keys -notcontains $v) } `
            -ValidationMessage 'Lowercase, unique, alphanumeric+_-.'
        $id = Read-PromptString -Label "$arch -> MG resource ID" `
            -Validator { param($v) Test-MgResourceId $v }
        $mgs[$arch] = $id
    }
    $Inputs.management_group_ids = $mgs
}

function Configure-Network {
    param([hashtable] $Inputs)

    $current = $Inputs.hub_virtual_network_resource_id
    $useRemoteGateways = [bool]($Inputs.hub_virtual_network_use_remote_gateways ?? $false)
    $summary = if ($current) {
        @(
            "hub_virtual_network_resource_id = $current"
            "hub_virtual_network_use_remote_gateways = $useRemoteGateways"
        )
    }
    else {
        @('(no hub VNet configured)')
    }
    if (-not (Edit-Group -Title 'Hub VNet (optional)' -SummaryLines $summary)) { return }

    $Inputs.hub_virtual_network_resource_id = Read-PromptString `
        -Label 'hub_virtual_network_resource_id' `
        -Default ($current ?? '') `
        -HelpText 'Full resource ID of the platform hub VNet. Leave empty if no hub.' `
        -AllowEmpty
    $Inputs.hub_virtual_network_use_remote_gateways = if ($Inputs.hub_virtual_network_resource_id) {
        Read-PromptBool `
            -Label 'Use a virtual network gateway in the hub?' `
            -Default $useRemoteGateways `
            -HelpText 'Enable only when the hub VNet has a gateway configured for gateway transit.'
    }
    else {
        $false
    }
}

function Configure-Tags {
    param([hashtable] $Inputs)

    $current = $Inputs.tags
    $summary = if ($current -and $current.Keys.Count -gt 0) {
        @($current.Keys | ForEach-Object { "tags[$_] = $($current[$_])" })
    }
    else { @('(no bootstrap tags)') }
    if (-not (Edit-Group -Title 'Bootstrap-resource tags' -SummaryLines $summary)) { return }

    $Inputs.tags = Read-MapPrompt -Label 'tags' -Current $current -Defaults ([ordered]@{
            managedby = 'terraform'
            workload  = 'sub-vending-bootstrap'
            owner     = 'platform-team'
        })

    $currentMandatory = $Inputs.mandatory_tags
    $defaults = [ordered]@{
        managedby  = 'terraform'
        source     = 'avm-ptn-alz-sub-vending'
        deployedby = 'subscription-vending-pipeline'
    }
    Write-Host ''
    Write-Host '    mandatory_tags are merged into every vended subscription.' -ForegroundColor DarkGray
    $Inputs.mandatory_tags = Read-MapPrompt -Label 'mandatory_tags' -Current $currentMandatory -Defaults $defaults
}

function Read-MapPrompt {
    <#
    Returns an ordered hashtable. If the operator accepts defaults, returns
    them. Otherwise loops "key=value" entries.
    #>
    param(
        [string] $Label,
        $Current,
        [System.Collections.Specialized.OrderedDictionary] $Defaults
    )
    $start = if ($Current -and $Current.Count -gt 0) { $Current } else { $Defaults }
    if ($start.Count -gt 0) {
        Write-Host "    Current ${Label}:" -ForegroundColor DarkGray
        foreach ($k in $start.Keys) { Write-Host "      $k = $($start[$k])" -ForegroundColor DarkGray }
    }
    $custom = Read-PromptBool -Label "Customize $Label?" -Default $false
    if (-not $custom) { return $start }

    $map = [ordered]@{}
    Write-Host "    Enter $Label as key=value, one per line. Empty line to finish." -ForegroundColor DarkGray
    while ($true) {
        $line = (Read-Host '      ').Trim()
        if ($line -eq '') { break }
        if ($line -notmatch '^([A-Za-z0-9._-]+)=(.+)$') {
            Write-Fail '  Format: key=value (key: alphanumeric / . _ -)'
            continue
        }
        $map[$Matches[1]] = $Matches[2]
    }
    return $map
}

function Configure-CostAllocation {
    param([hashtable] $Inputs)

    $current = $Inputs.cost_allocation_tag
    $summary = @()
    if ($current) {
        if ($current.name) { $summary += "cost_allocation_tag.name     = $($current.name)" }
        if ($current.Contains('required')) { $summary += "cost_allocation_tag.required = $($current.required)" }
        if ($current.pattern) { $summary += "cost_allocation_tag.pattern  = $($current.pattern)" }
    }
    else { $summary += '(defaults: name=projectcode, required=false, no pattern)' }
    if (-not (Edit-Group -Title 'Cost-allocation tag' -SummaryLines $summary)) { return }

    $tag = [ordered]@{}
    $defaultName = if ([string]::IsNullOrEmpty($current.name)) { 'projectcode' } else { $current.name }
    $tag.name = Read-PromptString -Label 'cost_allocation_tag.name' `
        -Default $defaultName `
        -HelpText 'Tag KEY emitted on every vended subscription in addition to costcenter. CAF convention: lowercase, 2-128 chars, starts with letter.' `
        -Validator { param($v) $v -match '^[a-z][a-z0-9]{1,127}$' } `
        -ValidationMessage 'Lowercase alphanumeric, 2-128 chars, starts with a letter.'

    $currentReq = if ($current -and $current.Contains('required')) { [bool] $current.required } else { $false }
    $tag.required = Read-PromptBool -Label 'cost_allocation_tag.required' `
        -Default $currentReq `
        -HelpText 'If true, sub.yaml without costAllocationCode fails plan.'

    $usePattern = Read-PromptBool -Label 'Validate value with a regex pattern?' `
        -Default ($current -and -not [string]::IsNullOrWhiteSpace($current.pattern)) `
        -HelpText "Optional Terraform regex. Anchors recommended (e.g. '^[A-Z]{3}-[0-9]{4}$')."
    if ($usePattern) {
        $tag.pattern = Read-PromptString -Label 'cost_allocation_tag.pattern' `
            -Default (($current.pattern ?? '') -as [string]) `
            -HelpText 'Anchor with ^ ... $ for full-match.' `
            -AllowEmpty
    }
    $Inputs.cost_allocation_tag = $tag
}

function Configure-CodeOwners {
    param([hashtable] $Inputs)

    $summary = @()
    if ($Inputs.codeowners_default_team) { $summary += "codeowners_default_team = $($Inputs.codeowners_default_team)" }
    $arch = $Inputs.codeowners_archetype_teams
    if ($arch -and $arch.Keys.Count -gt 0) {
        foreach ($k in $arch.Keys) { $summary += "codeowners_archetype_teams[$k] = $($arch[$k] -join ', ')" }
    }
    if ($summary.Count -eq 0) { $summary += '(not configured -- placeholder will ship)' }
    if (-not (Edit-Group -Title 'CODEOWNERS for the seeded repo' -SummaryLines $summary)) { return }

    $Inputs.codeowners_default_team = Read-PromptString `
        -Label 'codeowners_default_team' `
        -Default ($Inputs.codeowners_default_team ?? '') `
        -HelpText 'Default reviewer for the seeded repo (e.g. @your-org/platform-team).' `
        -Validator { param($v) Test-GitHubHandle $v } `
        -ValidationMessage 'Format: @user or @org/team-slug.'

    $existing = $Inputs.codeowners_archetype_teams ?? [ordered]@{}
    $per = [ordered]@{}
    foreach ($archKey in @('corp', 'online', 'sandbox')) {
        $defaultStr = if ($existing[$archKey]) { ($existing[$archKey] -join ',') } else { '' }
        $raw = Read-PromptString -Label "additional reviewers for landingzones/$archKey/ (comma-separated)" `
            -Default $defaultStr `
            -HelpText 'Empty to fall back to the default team only.' `
            -AllowEmpty `
            -Validator { param($v) ($v -eq '') -or (($v -split ',' | ForEach-Object { Test-GitHubHandle $_.Trim() }) -notcontains $false) } `
            -ValidationMessage 'Each entry must be @user or @org/team.'
        if ($raw -ne '') {
            $per[$archKey] = @($raw -split ',' | ForEach-Object { $_.Trim() })
        }
    }
    $Inputs.codeowners_archetype_teams = $per
}

function Configure-Skeleton {
    param([hashtable] $Inputs)

    $summary = @()
    if ($Inputs.Contains('copy_skeleton_files')) { $summary += "copy_skeleton_files     = $($Inputs.copy_skeleton_files)" }
    if ($Inputs.skeleton_commit_author) { $summary += "skeleton_commit_author  = $($Inputs.skeleton_commit_author)" }
    if ($Inputs.skeleton_commit_email) { $summary += "skeleton_commit_email   = $($Inputs.skeleton_commit_email)" }
    if (-not (Edit-Group -Title 'Skeleton seeding' -SummaryLines $summary)) { return }

    $currentCopy = if ($Inputs.Contains('copy_skeleton_files')) { [bool] $Inputs.copy_skeleton_files } else { $true }
    $Inputs.copy_skeleton_files = Read-PromptBool `
        -Label 'copy_skeleton_files' `
        -Default $currentCopy `
        -HelpText 'If true, bootstrap copies skeleton files into the seeded repo. Disable after the first apply to make the seeded repo free-form.'

    $Inputs.skeleton_commit_author = Read-PromptString `
        -Label 'skeleton_commit_author' `
        -Default ($Inputs.skeleton_commit_author ?? 'sub-vending-bootstrap') `
        -HelpText 'Author for skeleton-seed commits in the seeded repo.'

    $Inputs.skeleton_commit_email = Read-PromptString `
        -Label 'skeleton_commit_email' `
        -Default ($Inputs.skeleton_commit_email ?? 'platform-bootstrap@example.local') `
        -HelpText 'Email for skeleton-seed commits.' `
        -Validator { param($v) $v -match '^[^@\s]+@[^@\s]+\.[^@\s]+$' } `
        -ValidationMessage 'Enter a valid email address.'
}

function Invoke-Configure {
    param([hashtable] $Inputs)
    if ($NonInteractive) {
        Write-Header 'Configure: skipping (NonInteractive)'
        return
    }
    Configure-IdentityLocation $Inputs ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    if ($Inputs.starter_name -eq 'terraform') {
        Configure-State $Inputs        ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    }
    else {
        $Inputs.Remove('state_storage_account_resource_group_name')
        $Inputs.Remove('state_storage_account_name')
        $Inputs.Remove('state_container_name')
        Save-Inputs -Path $InputsPath -Inputs $Inputs
        Write-Skip 'Terraform runtime state configuration is not used by the Bicep starter.'
    }
    Configure-Rbac $Inputs             ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-GitHubRepo $Inputs       ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-BranchProtection $Inputs ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-ProductionEnv $Inputs    ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-BillingScopes $Inputs    ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-ManagementGroups $Inputs ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-Network $Inputs          ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-Tags $Inputs             ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-CostAllocation $Inputs   ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-CodeOwners $Inputs       ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Configure-Skeleton $Inputs         ; Save-Inputs -Path $InputsPath -Inputs $Inputs
    Write-Host ''
    Write-Ok "Configure complete. Inputs saved to: $InputsPath"
}


# =============================================================================
# Section 6 -- Validate phase (talk to Azure / GitHub APIs)
# =============================================================================

function Invoke-Validate {
    param([hashtable] $Inputs)
    Write-Header 'Validate: checking inputs against Azure + GitHub'

    $required = @(
        'tenant_id', 'platform_subscription_id', 'location',
        'uami_resource_group_name', 'alz_root_management_group_id',
        'connectivity_subscription_id', 'github_owner', 'github_repository_name',
        'billing_scopes', 'management_group_ids'
    )
    if ($Inputs.starter_name -eq 'terraform') {
        $required += @('state_storage_account_resource_group_name', 'state_storage_account_name')
    }
    if ($Inputs.github_oidc_subject_mode -eq 'immutable') {
        $required += 'github_owner_id'
    }
    $missing = $required | Where-Object { -not $Inputs.Contains($_) -or $null -eq $Inputs[$_] -or $Inputs[$_] -eq '' }
    if ($missing) {
        throw "Missing required inputs: $($missing -join ', '). Run -Phase configure."
    }

    $ok = $true

    # Switch to the target tenant + subscription
    try {
        & az account set --subscription $Inputs.platform_subscription_id 2>$null
        $acct = (& az account show 2>$null) | ConvertFrom-Json
        if ($acct.tenantId -ne $Inputs.tenant_id) {
            Write-Fail "Active az tenant ($($acct.tenantId)) != configured tenant_id ($($Inputs.tenant_id))."
            $ok = $false
        }
        else {
            Write-Ok "Az session matches platform sub $($Inputs.platform_subscription_id) in tenant $($Inputs.tenant_id)."
        }
    }
    catch {
        Write-Fail "az account set failed: $($_.Exception.Message)"
        $ok = $false
    }

    # UAMI resource group
    try {
        $rg = (& az group show --name $Inputs.uami_resource_group_name 2>$null) | ConvertFrom-Json
        if ($rg) { Write-Ok "UAMI RG $($rg.name) found in $($rg.location)." }
        else { Write-Fail "UAMI RG '$($Inputs.uami_resource_group_name)' not found in current sub."; $ok = $false }
    }
    catch { Write-Fail "UAMI RG check failed: $($_.Exception.Message)"; $ok = $false }

    # Terraform runtime state storage account
    if ($Inputs.starter_name -eq 'terraform') {
        try {
            $sa = (& az storage account show `
                    --name $Inputs.state_storage_account_name `
                    --resource-group $Inputs.state_storage_account_resource_group_name 2>$null) | ConvertFrom-Json
            if ($sa) { Write-Ok "State SA $($sa.name) found." }
            else { Write-Fail "State SA '$($Inputs.state_storage_account_name)' not found."; $ok = $false }
        }
        catch { Write-Fail "Storage account check failed: $($_.Exception.Message)"; $ok = $false }
    }

    # Management groups
    foreach ($k in $Inputs.management_group_ids.Keys) {
        $mgRid = $Inputs.management_group_ids[$k]
        if (-not (Test-MgResourceId $mgRid)) {
            Write-Fail "management_group_ids[$k] '$mgRid' is not a full MG resource ID."; $ok = $false; continue
        }
        $mgName = ($mgRid -split '/')[-1]
        try {
            $mg = (& az account management-group show --name $mgName 2>$null) | ConvertFrom-Json
            if ($mg) { Write-Ok "MG '$mgName' (archetype: $k) exists." }
            else { Write-Fail "MG '$mgName' not found."; $ok = $false }
        }
        catch { Write-Fail "MG '$mgName' lookup failed: $($_.Exception.Message)"; $ok = $false }
    }

    # Root MG (bare name)
    try {
        $rootMg = (& az account management-group show --name $Inputs.alz_root_management_group_id 2>$null) | ConvertFrom-Json
        if ($rootMg) { Write-Ok "Root MG '$($Inputs.alz_root_management_group_id)' exists." }
        else { Write-Fail "Root MG '$($Inputs.alz_root_management_group_id)' not found."; $ok = $false }
    }
    catch { Write-Fail "Root MG lookup failed: $($_.Exception.Message)"; $ok = $false }

    # billing_scopes must contain default + correct nested shape
    if (-not $Inputs.billing_scopes.Contains('default')) {
        Write-Fail 'billing_scopes is missing the required "default" entry.'; $ok = $false
    }
    foreach ($k in $Inputs.billing_scopes.Keys) {
        $bs = $Inputs.billing_scopes[$k]
        $type = $bs.agreement_type
        if (-not @('EA', 'MCA', 'MPA') -contains $type) {
            Write-Fail "billing_scopes[$k].agreement_type '$type' is not EA/MCA/MPA."; $ok = $false; continue
        }
        $expectedNested = $type.ToLower()
        $hasMatching = $bs.Contains($expectedNested) -and $null -ne $bs[$expectedNested]
        $stray = @('ea', 'mca', 'mpa') | Where-Object { $_ -ne $expectedNested -and $bs.Contains($_) -and $null -ne $bs[$_] }
        if (-not $hasMatching) {
            Write-Fail "billing_scopes[$k]: missing nested '$expectedNested' object."; $ok = $false
        }
        elseif ($stray) {
            Write-Fail "billing_scopes[$k]: has stray nested object(s) $($stray -join ', '). Only '$expectedNested' should be set."; $ok = $false
        }
        else {
            Write-Ok "billing_scopes[$k] ($type) shape OK."
        }
    }

    Write-ProductionReviewerGuardrail -Inputs $Inputs -Validation

    # GitHub repo presence (only if create_github_repository=false)
    if (-not [bool] $Inputs.create_github_repository) {
        try {
            $r = (& gh api "repos/$($Inputs.github_owner)/$($Inputs.github_repository_name)" 2>$null) | ConvertFrom-Json
            if ($r -and $r.permissions -and ($r.permissions.admin -or $r.permissions.maintain)) {
                Write-Ok "GitHub repo $($r.full_name) exists and token has admin/maintain."
            }
            elseif ($r) {
                Write-Warn "GitHub repo $($r.full_name) exists but token lacks admin/maintain. Branch protection may fail."
            }
            else {
                Write-Fail "GitHub repo $($Inputs.github_owner)/$($Inputs.github_repository_name) not found, and create_github_repository=false."; $ok = $false
            }
        }
        catch { Write-Fail "GitHub repo lookup failed: $($_.Exception.Message)"; $ok = $false }
    }

    if (-not $ok) {
        throw 'Validate failed. Fix the items above (run -Phase configure to update inputs) and try again.'
    }
    Write-Host ''
    Write-Ok 'Validate complete.'
}


# =============================================================================
# Section 7 -- Render terraform.tfvars.json
# =============================================================================

function Render-Tfvars {
    param([hashtable] $Inputs, [string] $Path)
    Write-Header "Render: $Path"

    if (Test-Path $Path) {
        $existing = Get-Content -Path $Path -Raw
        if ($existing -notmatch '"managed_by_invoke_bootstrap"\s*:\s*true') {
            Write-Warn "$Path exists but was not rendered by Invoke-Bootstrap (the 'managed_by_invoke_bootstrap' sentinel is missing)."
            if (-not $NonInteractive) {
                $ans = Read-Host '    Overwrite anyway? [y/N]'
                if ($ans -notmatch '^(y|yes)$') {
                    throw 'Aborted at render. Move or remove the existing terraform.tfvars.json and re-run.'
                }
            }
        }
    }

    # Terraform's tfvars.json accepts any top-level keys mapped to variables.
    # We add a single sentinel key as a marker for our own drift detection;
    # Terraform would normally reject unknown variables but we declare it
    # below in variables.tf.
    $payload = [ordered]@{}
    foreach ($k in $Inputs.Keys) {
        if ($k -eq 'managed_by_invoke_bootstrap') { continue }
        $payload[$k] = $Inputs[$k]
    }
    $payload['managed_by_invoke_bootstrap'] = $true

    $json = ConvertTo-Json -InputObject $payload -Depth 32
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Path $tmp -Destination $Path -Force
    Write-Ok "Rendered $Path"
}


# =============================================================================
# Section 8 -- Terraform phase
# =============================================================================

function Invoke-Terraform {
    param([hashtable] $Inputs)
    Write-Header 'Terraform: init -> plan -> apply'

    # Tenant binding before every terraform call
    & az account set --subscription $Inputs.platform_subscription_id | Out-Null
    $env:ARM_TENANT_ID = $Inputs.tenant_id
    $env:ARM_SUBSCRIPTION_ID = $Inputs.platform_subscription_id
    # GITHUB_TOKEN already in process env from preflight

    $chdir = "-chdir=$ScriptRoot"

    # init
    $initArgs = @($chdir, 'init', '-input=false')
    if ($Reconfigure) { $initArgs += '-reconfigure' }
    Write-Info ("terraform " + ($initArgs -join ' '))
    & terraform @initArgs
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed (exit $LASTEXITCODE)" }

    # plan
    $planPath = Join-Path $ScriptRoot 'tfplan'
    $planArgs = @($chdir, 'plan', '-input=false', "-out=$planPath")
    Write-Info ("terraform " + ($planArgs -join ' '))
    & terraform @planArgs
    $planExit = $LASTEXITCODE
    if ($planExit -ne 0) { throw "terraform plan failed (exit $planExit)" }

    if ($PlanOnly) {
        Write-Host ''
        Write-Ok "Plan complete. Plan file: $planPath (not applying because -PlanOnly was set)."
        return
    }

    # apply gate
    if ($AutoApprove) {
        Write-Info 'Apply: -AutoApprove set; proceeding without prompt.'
    }
    elseif ($NonInteractive) {
        Write-Warn "NonInteractive without -AutoApprove -- plan-only path taken. Re-run with -AutoApprove to apply."
        return
    }
    else {
        Write-Host ''
        $ans = Read-Host '    Apply this plan? [y/N]'
        if ($ans -notmatch '^(y|yes)$') {
            Write-Warn 'Apply skipped.'
            return
        }
    }

    $applyArgs = @($chdir, 'apply', '-input=false', $planPath)
    Write-Info ("terraform " + ($applyArgs -join ' '))
    & terraform @applyArgs
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed (exit $LASTEXITCODE)" }

    Write-Header 'Outputs'
    & terraform $chdir output
    Write-Host ''
    Write-Host '    Next manual step:' -ForegroundColor Yellow
    Write-Host '      Grant SubscriptionCreator on each billing scope. See:' -ForegroundColor Yellow
    Write-Host "        terraform -chdir=$ScriptRoot output next_step_billing_role" -ForegroundColor Yellow
}


# =============================================================================
# Section 8.5 -- Destroy / teardown helpers (-Destroy mode)
# =============================================================================

function Get-RequiredInput {
    param([hashtable] $Inputs, [string] $Key)
    if (-not $Inputs.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace([string]$Inputs[$Key])) {
        throw "Sidecar is missing required key '$Key'. Cannot proceed."
    }
    return [string]$Inputs[$Key]
}

function Get-OptionalInput {
    param([hashtable] $Inputs, [string] $Key, $Default = $null)
    if (-not $Inputs.ContainsKey($Key)) { return $Default }
    $v = $Inputs[$Key]
    if ($null -eq $v) { return $Default }
    if ($v -is [string] -and [string]::IsNullOrWhiteSpace($v)) { return $Default }
    return $v
}

function Assert-DestroyTenant {
    param([hashtable] $Inputs)
    $expectedTenant = Get-RequiredInput -Inputs $Inputs -Key 'tenant_id'
    $rawTenant = & az account show --query tenantId -o tsv 2>$null
    $actualTenant = if ($rawTenant) { ([string]$rawTenant).Trim() } else { $null }
    if (-not $actualTenant) {
        throw "No active az session. Run 'az login --tenant $expectedTenant' and retry."
    }
    if ($actualTenant -ne $expectedTenant) {
        throw "az tenant mismatch. Expected: $expectedTenant  Actual: $actualTenant.`n   Run 'az login --tenant $expectedTenant' and retry. -Destroy refuses to operate cross-tenant."
    }
    Write-Ok "az session is on tenant $expectedTenant"
    $expectedSub = Get-RequiredInput -Inputs $Inputs -Key 'platform_subscription_id'
    & az account set --subscription $expectedSub | Out-Null
    Write-Ok "az subscription pinned to $expectedSub (platform sub)"
}

function Approve-Action {
    param(
        [string] $Action,
        [switch] $Destructive
    )
    if ($WhatIfPreference) {
        Write-Plan "[what-if] $Action"
        return $false
    }
    if ($AutoApprove) {
        Write-Plan $Action
        return $true
    }
    if ($NonInteractive) {
        throw "Refusing to '$Action' in -NonInteractive mode without -AutoApprove."
    }
    $color = if ($Destructive) { 'Red' } else { 'Yellow' }
    Write-Host ''
    Write-Host "  $Action" -ForegroundColor $color
    $answer = (Read-Host -Prompt '  Proceed? [y/N]').Trim()
    return $answer -match '^(y|yes)$'
}

function Get-AzResource {
    <#
      Wraps `az` calls so 'NotFound' / 'does not exist' returns $null
      instead of throwing. Captures stderr to a temp file so success-path
      stderr noise (deprecation warnings, telemetry) does NOT contaminate
      stdout when callers pipe the result to ConvertFrom-Json.
    #>
    param([scriptblock] $AzCall)
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $output = & $AzCall 2>$errFile
        if ($LASTEXITCODE -ne 0) {
            $err = (Get-Content -Path $errFile -Raw -ErrorAction SilentlyContinue)
            if ($err -and ($err -match '(?i)NotFound|does not exist|ResourceNotFound|ResourceGroupNotFound|could not be found')) {
                return $null
            }
            throw ($err ? $err : "az call failed (exit $LASTEXITCODE)")
        }
        $joined = if ($output -is [array]) { ($output -join "`n") } else { [string]$output }
        if ([string]::IsNullOrWhiteSpace($joined)) { return $null }
        return $joined
    }
    finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-GhApi {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        [switch] $AllowNotFound
    )
    try {
        $output = & gh api -X $Method $Path 2>&1
        if ($LASTEXITCODE -ne 0) {
            $err = ($output | Out-String)
            if ($AllowNotFound -and ($err -match '404|Not Found')) { return $null }
            throw "gh api $Method $Path failed: $err"
        }
        return ($output | Out-String).Trim()
    }
    catch {
        if ($AllowNotFound -and $_.Exception.Message -match '404|Not Found') { return $null }
        throw
    }
}

function Get-DestroyTargets {
    param([hashtable] $Inputs)

    Write-Header 'Discover: probing Azure + GitHub'

    $d = @{
        UamiObject              = $null
        UamiPrincipalId         = $null
        FederatedCredentials    = @()
        AzureRoleAssignments    = @()
        StateContainer          = $null
        StateContainerBlobCount = $null
        GitHubRepo              = $null
        BranchProtection        = $false
        ProductionEnvironment   = $false
        ActionsVariables        = @()
        BillingScopeReminders   = @()
    }

    $uamiRg   = Get-RequiredInput -Inputs $Inputs -Key 'uami_resource_group_name'
    $uamiName = Get-OptionalInput  -Inputs $Inputs -Key 'uami_name' -Default 'id-subvending-pipeline'

    $uamiJson = Get-AzResource { az identity show -g $uamiRg -n $uamiName -o json }
    if ($uamiJson) {
        $u = $uamiJson | ConvertFrom-Json
        $d.UamiObject = $u
        $d.UamiPrincipalId = $u.principalId
        Write-Ok "UAMI '$uamiName' in RG '$uamiRg' -- principalId $($u.principalId)"

        $ficJson = Get-AzResource { az identity federated-credential list -g $uamiRg --identity-name $uamiName -o json }
        if ($ficJson) {
            $fics = @($ficJson | ConvertFrom-Json)
            $d.FederatedCredentials = $fics
            Write-Ok "Federated credentials on UAMI: $($fics.Count)"
            foreach ($fic in $fics) { Write-Info "  - $($fic.name) -> $($fic.subject)" }
        }

        $raJson = Get-AzResource { az role assignment list --assignee $u.principalId --all -o json }
        if ($raJson) {
            $ras = @($raJson | ConvertFrom-Json)
            $d.AzureRoleAssignments = $ras
            Write-Ok "Azure role assignments granted to the UAMI: $($ras.Count)"
            foreach ($ra in $ras) { Write-Info "  - $($ra.roleDefinitionName) on $($ra.scope)" }
        }
    }
    else {
        Write-Warn "UAMI '$uamiName' in RG '$uamiRg' -- not found"
    }

    if ($Inputs.starter_name -eq 'terraform') {
        $saName   = Get-RequiredInput -Inputs $Inputs -Key 'state_storage_account_name'
        $contName = Get-OptionalInput  -Inputs $Inputs -Key 'state_container_name' -Default 'subvending-tfstate'

        $exists = Get-AzResource { az storage container exists --auth-mode login --account-name $saName --name $contName --query exists -o tsv }
        if ($exists -and $exists.Trim() -eq 'true') {
            $d.StateContainer = $contName
            $blobsRaw = Get-AzResource { az storage blob list --auth-mode login --account-name $saName --container-name $contName --query "length([])" -o tsv }
            $count = if ($blobsRaw) { [int]$blobsRaw.Trim() } else { 0 }
            $d.StateContainerBlobCount = $count
            if ($count -gt 0) {
                Write-Warn "State container '$contName' in '$saName' EXISTS, $count blob(s) -- vended-sub state. Container will NOT be deleted."
            } else {
                Write-Ok "State container '$contName' in '$saName' EXISTS and is empty"
            }
        } else {
            Write-Warn "State container '$contName' in '$saName' -- not found"
        }
    }

    $ghOwner  = Get-RequiredInput -Inputs $Inputs -Key 'github_owner'
    $ghRepo   = Get-OptionalInput -Inputs $Inputs -Key 'github_repository_name' -Default 'sub-vending'
    $ghBranch = Get-OptionalInput -Inputs $Inputs -Key 'github_default_branch' -Default 'main'
    $envName  = Get-OptionalInput -Inputs $Inputs -Key 'production_environment_name' -Default 'production'

    $repoJson = Invoke-GhApi -Method 'GET' -Path "/repos/$ghOwner/$ghRepo" -AllowNotFound
    if ($repoJson) {
        $d.GitHubRepo = "$ghOwner/$ghRepo"
        Write-Ok "GitHub repo '$ghOwner/$ghRepo' exists"

        $bp = Invoke-GhApi -Method 'GET' -Path "/repos/$ghOwner/$ghRepo/branches/$ghBranch/protection" -AllowNotFound
        if ($bp) { $d.BranchProtection = $true; Write-Ok "  Branch protection on '$ghBranch' is configured" }
        else     { Write-Info "  Branch protection on '$ghBranch' is NOT configured" }

        $env = Invoke-GhApi -Method 'GET' -Path "/repos/$ghOwner/$ghRepo/environments/$envName" -AllowNotFound
        if ($env) { $d.ProductionEnvironment = $true; Write-Ok "  Environment '$envName' exists" }
        else      { Write-Info "  Environment '$envName' does not exist" }

        $vars = Invoke-GhApi -Method 'GET' -Path "/repos/$ghOwner/$ghRepo/actions/variables" -AllowNotFound
        if ($vars) {
            $varObj = $vars | ConvertFrom-Json
            $managed = @('AZURE_CLIENT_ID', 'AZURE_TENANT_ID', 'AZURE_SUBSCRIPTION_ID',
                'VENDING_ENGINE', 'ALZ_ROOT_MANAGEMENT_GROUP_ID', 'AZURE_DEPLOYMENT_LOCATION')
            if ($Inputs.starter_name -eq 'terraform') {
                $managed += @('BACKEND_RESOURCE_GROUP_NAME', 'BACKEND_STORAGE_ACCOUNT_NAME', 'BACKEND_CONTAINER_NAME')
            }
            $hit = @($varObj.variables | Where-Object { $managed -contains $_.name } | ForEach-Object { $_.name })
            $d.ActionsVariables = $hit
            Write-Ok "  Actions variables managed: $($hit.Count) ($(($hit -join ', ')))"
        }
    } else {
        Write-Warn "GitHub repo '$ghOwner/$ghRepo' -- not found"
    }

    $bs = Get-OptionalInput -Inputs $Inputs -Key 'billing_scopes'
    if ($bs -and $d.UamiPrincipalId) {
        foreach ($k in $bs.Keys) {
            $entry = $bs[$k]
            $d.BillingScopeReminders += [PSCustomObject]@{
                Key           = $k
                AgreementType = $entry.agreement_type
                Detail        = $entry
            }
        }
    }

    return $d
}

function Invoke-TerraformDestroy {
    Write-Header 'Destroy: terraform destroy (local state present)'
    Push-Location $ScriptRoot
    try {
        if (-not (Test-Path '.terraform' -PathType Container)) {
            Write-Info 'Running terraform init so destroy can read the providers...'
            if ($WhatIfPreference) {
                Write-Plan '[what-if] terraform init'
            } else {
                & terraform init -input=false
                if ($LASTEXITCODE -ne 0) { throw "terraform init failed (exit $LASTEXITCODE)" }
            }
        }
        if ($WhatIfPreference) {
            Write-Plan '[what-if] terraform plan -destroy'
            & terraform plan -destroy -input=false -no-color
            return
        }
        if (-not $AutoApprove -and -not (Approve-Action -Action 'Run terraform destroy against bootstrap state' -Destructive)) {
            Write-Skip 'terraform destroy declined.'
            return
        }
        $destroyArgs = @('destroy', '-input=false', '-no-color')
        if ($AutoApprove) { $destroyArgs += '-auto-approve' }
        & terraform @destroyArgs
        if ($LASTEXITCODE -ne 0) { throw "terraform destroy failed (exit $LASTEXITCODE)" }
        Write-Ok 'terraform destroy completed.'
    }
    finally { Pop-Location }
}

function Invoke-ForceCleanup {
    param([hashtable] $Inputs, [hashtable] $Discovered)

    Write-Header 'Destroy: force-cleanup (no local Terraform state)'
    Write-Warn 'Local terraform.tfstate not found. Falling back to API deletes driven by the sidecar.'

    # Azure RBAC first (so role-assignment orphans don't outlive the UAMI)
    if ($Discovered.AzureRoleAssignments.Count -gt 0) {
        Write-Host ''
        Write-Header "Azure role assignments ($($Discovered.AzureRoleAssignments.Count))"
        foreach ($ra in $Discovered.AzureRoleAssignments) {
            $label = "$($ra.roleDefinitionName) on $($ra.scope)"
            if (-not (Approve-Action -Action "Remove role assignment: $label" -Destructive)) {
                Write-Skip $label; continue
            }
            & az role assignment delete --ids $ra.id 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Done $label } else { Write-Fail "Failed to delete: $label" }
        }
    }

    # UAMI (cascades FICs)
    if ($Discovered.UamiObject) {
        Write-Host ''
        Write-Header 'Pipeline UAMI'
        $u = $Discovered.UamiObject
        $label = "UAMI '$($u.name)' in RG '$($u.resourceGroup)' (deletes $($Discovered.FederatedCredentials.Count) FIC(s) implicitly)"
        if (Approve-Action -Action "Delete $label" -Destructive) {
            & az identity delete -g $u.resourceGroup -n $u.name 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Done $label } else { Write-Fail "Failed to delete $label" }
        } else { Write-Skip $label }
    }

    # State container (opt-in + empty-only)
    if ($Discovered.StateContainer) {
        Write-Host ''
        Write-Header 'Terraform state container'
        if (-not $IncludeStateContainer) {
            Write-Skip "State container '$($Discovered.StateContainer)' -- omit -IncludeStateContainer to keep it."
        }
        elseif ($Discovered.StateContainerBlobCount -gt 0) {
            Write-Fail "State container '$($Discovered.StateContainer)' has $($Discovered.StateContainerBlobCount) blob(s); refusing to delete (would orphan vended-sub state)."
            Write-Info "Clear it manually first:"
            Write-Info "  az storage blob delete-batch --auth-mode login --account-name $(Get-RequiredInput -Inputs $Inputs -Key 'state_storage_account_name') --source $($Discovered.StateContainer)"
        }
        else {
            $saName = Get-RequiredInput -Inputs $Inputs -Key 'state_storage_account_name'
            $label = "State container '$($Discovered.StateContainer)' in '$saName'"
            if (Approve-Action -Action "Delete $label (empty)" -Destructive) {
                & az storage container delete --auth-mode login --account-name $saName --name $Discovered.StateContainer 2>$null
                if ($LASTEXITCODE -eq 0) { Write-Done $label } else { Write-Fail "Failed to delete $label" }
            } else { Write-Skip $label }
        }
    }

    # GitHub
    if ($Discovered.GitHubRepo) {
        Write-Host ''
        Write-Header "GitHub repo '$($Discovered.GitHubRepo)'"
        $ghOwner  = Get-RequiredInput -Inputs $Inputs -Key 'github_owner'
        $ghRepo   = Get-OptionalInput -Inputs $Inputs -Key 'github_repository_name' -Default 'sub-vending'
        $ghBranch = Get-OptionalInput -Inputs $Inputs -Key 'github_default_branch' -Default 'main'
        $envName  = Get-OptionalInput -Inputs $Inputs -Key 'production_environment_name' -Default 'production'

        if ($Discovered.BranchProtection) {
            $label = "Branch protection on '$ghBranch'"
            if (Approve-Action -Action "Remove $label" -Destructive) {
                Invoke-GhApi -Method 'DELETE' -Path "/repos/$ghOwner/$ghRepo/branches/$ghBranch/protection" -AllowNotFound | Out-Null
                Write-Done $label
            } else { Write-Skip $label }
        }
        if ($Discovered.ProductionEnvironment) {
            $label = "Environment '$envName'"
            if (Approve-Action -Action "Remove $label" -Destructive) {
                Invoke-GhApi -Method 'DELETE' -Path "/repos/$ghOwner/$ghRepo/environments/$envName" -AllowNotFound | Out-Null
                Write-Done $label
            } else { Write-Skip $label }
        }
        foreach ($v in $Discovered.ActionsVariables) {
            $label = "Actions variable '$v'"
            if (Approve-Action -Action "Remove $label" -Destructive) {
                Invoke-GhApi -Method 'DELETE' -Path "/repos/$ghOwner/$ghRepo/actions/variables/$v" -AllowNotFound | Out-Null
                Write-Done $label
            } else { Write-Skip $label }
        }
        if ($IncludeGitHubRepo) {
            $label = "Repository '$($Discovered.GitHubRepo)' (seeded files, history, PRs, issues)"
            if (Approve-Action -Action "DELETE $label" -Destructive) {
                Invoke-GhApi -Method 'DELETE' -Path "/repos/$ghOwner/$ghRepo" | Out-Null
                Write-Done $label
            } else { Write-Skip $label }
        } else {
            Write-Skip "Repository '$($Discovered.GitHubRepo)' -- omit -IncludeGitHubRepo to keep it."
        }
    }
}

function Show-BillingReminders {
    param([hashtable] $Inputs, [hashtable] $Discovered)
    if (-not $Discovered.UamiPrincipalId -and ($Discovered.BillingScopeReminders.Count -eq 0)) { return }

    Write-Host ''
    Write-Header 'Billing scope: SubscriptionCreator role (MANUAL revoke required)'
    Write-Warn 'The bootstrap module never grants or revokes the billing-scope role -- it is intentionally out-of-band. Run the relevant command(s) below to clean up.'

    foreach ($r in $Discovered.BillingScopeReminders) {
        $principalId = $Discovered.UamiPrincipalId
        $v = $r.Detail
        switch ($r.AgreementType) {
            'EA' {
                Write-Info "EA  ($($r.Key)):"
                Write-Host "  # Remove the SP as enrollment-account 'Owner':" -ForegroundColor DarkGray
                Write-Host "  az billing enrollment-account owner list --enrollment-account-id '$($v.ea.enrollment_account_id)'" -ForegroundColor DarkGray
                Write-Host "  # then 'az billing enrollment-account owner remove --owner-id ...' for the matching entry." -ForegroundColor DarkGray
            }
            'MCA' {
                Write-Info "MCA ($($r.Key)):"
                Write-Host "  # Portal: Cost Management + Billing -> Billing profile '$($v.mca.billing_profile_name)' -> Invoice section '$($v.mca.invoice_section_name)' -> Access control -> remove Azure subscription creator." -ForegroundColor DarkGray
            }
            'MPA' {
                Write-Info "MPA ($($r.Key)):"
                Write-Host "  az role assignment delete --assignee-object-id '$principalId' --scope '/providers/Microsoft.Billing/billingAccounts/$($v.mpa.billing_account_name)/customers/$($v.mpa.customer_id)'" -ForegroundColor DarkGray
            }
            default {
                Write-Warn "Unknown agreement_type for billing scope '$($r.Key)' -- review and revoke manually."
            }
        }
    }
}

function Invoke-CleanBootstrapFolder {
    Write-Host ''
    Write-Header 'Local bootstrap folder cleanup'
    $targets = @(
        (Join-Path $ScriptRoot '.terraform'),
        (Join-Path $ScriptRoot '.terraform.lock.hcl'),
        (Join-Path $ScriptRoot 'terraform.tfstate'),
        (Join-Path $ScriptRoot 'terraform.tfstate.backup'),
        (Join-Path $ScriptRoot 'tfplan'),
        $InputsPath,
        ($InputsPath + '.bak'),
        $TfvarsPath
    )
    foreach ($t in $targets) {
        if (Test-Path -LiteralPath $t) {
            if ($WhatIfPreference) { Write-Plan "[what-if] Remove $t"; continue }
            Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
            Write-Done "local: $t"
        }
    }
}


# =============================================================================
# Section 9 -- Main dispatcher
# =============================================================================

$mode = if ($Destroy) { 'DESTROY' } elseif ($CleanBootstrapFolder -and -not $PSBoundParameters.ContainsKey('Phase')) { 'CLEAN-ONLY' } else { 'BOOTSTRAP' }

Write-Banner "Sub-Vending Wizard -- mode: $mode"
Write-Host "  ScriptRoot:  $ScriptRoot"
Write-Host "  Engine:      $Engine"
Write-Host "  InputsPath:  $InputsPath"
Write-Host "  TfvarsPath:  $TfvarsPath"
if ($mode -eq 'BOOTSTRAP') { Write-Host "  Phase:       $Phase" }
if ($WhatIfPreference)     { Write-Warn 'Running in -WhatIf mode: no changes will be made.' }

$Inputs = Get-Inputs -Path $InputsPath
$starterWasPersisted = $Inputs.Contains('starter_name')
if ($starterWasPersisted -and $Inputs.starter_name -ne $starterName) {
    throw "The saved bootstrap uses starter '$($Inputs.starter_name)'. Engine changes require a separate migration or a new bootstrap configuration."
}
if ($starterManifest.availability -ne 'Available') {
    throw "The $($starterManifest.displayName) starter is $($starterManifest.availability.ToLowerInvariant()) and cannot be selected."
}
$Inputs.starter_name = $starterName
if (-not $starterWasPersisted -and (Test-Path -LiteralPath $InputsPath -PathType Leaf)) {
    Save-Inputs -Path $InputsPath -Inputs $Inputs
}

try {
    switch ($mode) {

        'BOOTSTRAP' {
            if ($Phase -in @('preflight', 'all') -and -not $SkipPreflight) {
                Invoke-Preflight -Inputs $Inputs
            }
            if ($Phase -in @('configure', 'all')) {
                Invoke-Configure -Inputs $Inputs
            }
            if ($Phase -in @('validate', 'all')) {
                Invoke-Validate -Inputs $Inputs
            }
            if ($Phase -in @('terraform', 'all')) {
                Render-Tfvars -Inputs $Inputs -Path $TfvarsPath
                Invoke-Terraform -Inputs $Inputs
            }
        }

        'DESTROY' {
            if ($Inputs.Count -eq 0) {
                throw "No sidecar found at $InputsPath. -Destroy needs the sidecar to know what to clean up. If the sidecar is lost too, you'll have to clean up by hand."
            }
            if (-not $SkipPreflight) {
                Invoke-Preflight -Inputs $Inputs
            }
            Assert-DestroyTenant -Inputs $Inputs
            $discovered = Get-DestroyTargets -Inputs $Inputs

            $tfStatePath = Join-Path $ScriptRoot 'terraform.tfstate'
            if (Test-Path -LiteralPath $tfStatePath) {
                Invoke-TerraformDestroy
            }
            else {
                Invoke-ForceCleanup -Inputs $Inputs -Discovered $discovered
            }
            Show-BillingReminders -Inputs $Inputs -Discovered $discovered
        }

        'CLEAN-ONLY' {
            # Standalone -CleanBootstrapFolder. No Azure / GitHub action.
            Write-Info 'Standalone local cleanup mode (no -Destroy specified).'
        }
    }

    if ($CleanBootstrapFolder) {
        Invoke-CleanBootstrapFolder
    }

    Write-Host ''
    Write-Ok 'Done.'
    if ($mode -eq 'DESTROY') {
        Write-Info 'Re-run without -Destroy to bootstrap again with corrected inputs.'
    }
}
catch {
    Write-Host ''
    Write-Fail $_.Exception.Message
    exit 1
}
