#Requires -Version 7.2

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repositoryRoot 'powershell/SubscriptionVending/SubscriptionVending.psd1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "subscription-vending-tests-$([guid]::NewGuid())"
$bootstrapPath = Join-Path $testRoot 'bootstrap'
$capturePath = Join-Path $testRoot 'arguments.json'
$starterRoot = Join-Path $repositoryRoot 'starters'
$testStarterRoot = Join-Path $testRoot 'starters'
$legacyBootstrapPath = Join-Path $repositoryRoot 'bootstrap/Invoke-Bootstrap.ps1'

function Assert-Equal {
  param(
    [Parameter(Mandatory)] $Expected,
    [Parameter(Mandatory)] $Actual,
    [Parameter(Mandatory)] [string] $Message
  )

  if ($Expected -ne $Actual) {
    throw "$Message Expected '$Expected', got '$Actual'."
  }
}

function Assert-Throws {
  param(
    [Parameter(Mandatory)] [scriptblock] $Script,
    [Parameter(Mandatory)] [string] $MessagePattern
  )

  try {
    & $Script
  }
  catch {
    if ($_.Exception.Message -notlike $MessagePattern) {
      throw "Expected error matching '$MessagePattern', got '$($_.Exception.Message)'."
    }
    return
  }
  throw "Expected error matching '$MessagePattern', but no error was thrown."
}

function Assert-Matches {
  param(
    [Parameter(Mandatory)] [string] $Value,
    [Parameter(Mandatory)] [string] $Pattern,
    [Parameter(Mandatory)] [string] $Message
  )

  if ($Value -notmatch $Pattern) {
    throw "$Message Pattern '$Pattern' was not found."
  }
}

try {
  New-Item -ItemType Directory -Path $bootstrapPath -Force | Out-Null
  Copy-Item -LiteralPath $starterRoot -Destination $testStarterRoot -Recurse
  New-Item -ItemType Directory -Path (Join-Path $testRoot 'terraform') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'bicep') -Destination (Join-Path $testRoot 'bicep') -Recurse
  New-Item -ItemType Directory -Path (Join-Path $testRoot 'landingzones') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $testRoot '.github/workflows') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $testRoot '.github/scripts') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $testRoot 'landingzones/sub.schema.json') -Value '{}'
  Set-Content -LiteralPath (Join-Path $testRoot '.github/workflows/pr-validate.yml') -Value 'name: test'
  Set-Content -LiteralPath (Join-Path $testRoot '.github/workflows/apply.yml') -Value 'name: test'
  Set-Content -LiteralPath (Join-Path $testRoot '.github/scripts/discover-subs.sh') -Value '# test'
  @'
param(
  [string] $Engine,
  [string] $StarterRoot,
  [string] $Phase,
  [string] $ScriptRoot,
  [switch] $NonInteractive,
  [switch] $AutoApprove,
  [switch] $PlanOnly,
  [switch] $Reconfigure,
  [switch] $SkipPreflight,
  [string] $InputsPath,
  [string] $TfvarsPath
)
$strictModeAllowsMissingKey = $true
try {
  $probe = @{}
  $null = $probe.optional
}
catch {
  $strictModeAllowsMissingKey = $false
}
$capture = @{} + $PSBoundParameters
$capture.strict_mode_allows_missing_key = $strictModeAllowsMissingKey
$capture | ConvertTo-Json | Set-Content -LiteralPath $env:SUBSCRIPTION_VENDING_TEST_CAPTURE
'@ | Set-Content -LiteralPath (Join-Path $bootstrapPath 'Invoke-Bootstrap.ps1')

  $env:SUBSCRIPTION_VENDING_TEST_CAPTURE = $capturePath
  Import-Module $modulePath -Force

  $commands = @(Get-Command -Module SubscriptionVending | Select-Object -ExpandProperty Name)
  Assert-Equal 4 $commands.Count 'Unexpected exported command count.'
  Assert-Equal $false (Get-Command Initialize-SubscriptionVending).Parameters.ContainsKey('WhatIf') 'Initialize must not expose unsafe WhatIf behavior.'

  $engines = @(Get-SubscriptionVendingEngine)
  Assert-Equal 'Available' ($engines | Where-Object Name -eq 'Terraform').Availability 'Terraform availability is incorrect.'
  Assert-Equal 'Available' ($engines | Where-Object Name -eq 'Bicep').Availability 'Bicep availability is incorrect.'
  Assert-Equal '1.0' ($engines | Where-Object Name -eq 'Terraform').ContractVersion 'Terraform contract version is incorrect.'

  $starterResults = @(Test-SubscriptionVendingStarter)
  Assert-Equal 2 $starterResults.Count 'Unexpected starter validation result count.'
  Assert-Equal 26 ($starterResults | Where-Object Name -eq 'Terraform').ImplementedCapabilities 'Terraform capability count is incorrect.'
  Assert-Equal 26 ($starterResults | Where-Object Name -eq 'Bicep').ImplementedCapabilities 'Bicep capability count is incorrect.'
  $terraformManifest = Get-Content -LiteralPath (Join-Path $starterRoot 'terraform/starter.json') -Raw | ConvertFrom-Json
  Assert-Equal 'terraform/' $terraformManifest.package.includePrefixes[0] 'Terraform package prefix is incorrect.'
  $starterContract = Get-Content -LiteralPath (Join-Path $starterRoot 'starter-contract.json') -Raw | ConvertFrom-Json
  Assert-Equal $true ('terraform/' -in $starterContract.packageRoots) 'Terraform package root is missing from the contract.'
  Assert-Equal $true ('bicep/' -in $starterContract.packageRoots) 'Bicep package root is missing from the contract.'
  $sampleFiles = @('README.md', 'scripts/Grant-SubscriptionCreatorRole.ps1', 'terraform/main.tf', 'bicep/main.bicep')
  $terraformPackage = @(
    $sampleFiles | Where-Object {
      $file = $_
      $isEngineFile = @($starterContract.packageRoots | Where-Object { $file.StartsWith($_) }).Count -gt 0
      $isSelectedFile = @($terraformManifest.package.includePrefixes | Where-Object { $file.StartsWith($_) }).Count -gt 0
      -not $isEngineFile -or $isSelectedFile
    }
  )
  Assert-Equal $true ('README.md' -in $terraformPackage) 'Common files must be included in the Terraform package.'
  Assert-Equal $true ('scripts/Grant-SubscriptionCreatorRole.ps1' -in $terraformPackage) 'The billing role helper must be included in the Terraform package.'
  Assert-Equal $true ('terraform/main.tf' -in $terraformPackage) 'Terraform files must be included in the Terraform package.'
  Assert-Equal $false ('bicep/main.bicep' -in $terraformPackage) 'Non-selected Bicep files must be excluded from the Terraform package.'
  $acceleratorManifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'accelerator.json') -Raw | ConvertFrom-Json
  Assert-Matches $acceleratorManifest.version '^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$' 'Accelerator version must be a semantic release identifier.'
  Assert-Equal 'v0.4.0' $acceleratorManifest.version 'Accelerator release version is incorrect.'
  Assert-Equal 'haflidif/alz-sub-vending-terraform-accelerator' $acceleratorManifest.repository 'Accelerator source repository is incorrect.'
  $upgradeManifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'upgrade-manifest.json') -Raw | ConvertFrom-Json
  Assert-Equal '1.0' $upgradeManifest.schemaVersion 'Upgrade manifest version is incorrect.'
  Assert-Equal $true ('terraform/terraform.auto.tfvars' -in $upgradeManifest.engines.terraform.excludeFiles) 'Terraform rendered configuration must be repository-owned.'
  Assert-Equal $true ('bicep/platform.json' -in $upgradeManifest.engines.bicep.excludeFiles) 'Bicep rendered configuration must be repository-owned.'
  Assert-Equal $true ('docs/proposals/' -in $upgradeManifest.common.excludePrefixes) 'Source-only proposals must be excluded from upgrades.'
  Assert-Equal $true (Test-Path -LiteralPath (Join-Path $repositoryRoot 'scripts/Update-SubscriptionVending.ps1')) 'Upgrade command is missing.'
  $bicepManifest = Get-Content -LiteralPath (Join-Path $starterRoot 'bicep/starter.json') -Raw | ConvertFrom-Json
  Assert-Equal 'bicep' $bicepManifest.runtime.enginePath 'Bicep engine path is incorrect.'
  Assert-Equal 'arm-what-if' $bicepManifest.runtime.previewMode 'Bicep preview mode is incorrect.'
  $bicepPackage = @(
    $sampleFiles | Where-Object {
      $file = $_
      $isEngineFile = @($starterContract.packageRoots | Where-Object { $file.StartsWith($_) }).Count -gt 0
      $isSelectedFile = @($bicepManifest.package.includePrefixes | Where-Object { $file.StartsWith($_) }).Count -gt 0
      -not $isEngineFile -or $isSelectedFile
    }
  )
  Assert-Equal $true ('README.md' -in $bicepPackage) 'Common files must be included in the Bicep package.'
  Assert-Equal $true ('scripts/Grant-SubscriptionCreatorRole.ps1' -in $bicepPackage) 'The billing role helper must be included in the Bicep package.'
  Assert-Equal $true ('bicep/main.bicep' -in $bicepPackage) 'Bicep files must be included in the Bicep package.'
  Assert-Equal $false ('terraform/main.tf' -in $bicepPackage) 'Non-selected Terraform files must be excluded from the Bicep package.'

  $bootstrapMain = Get-Content -LiteralPath (Join-Path $repositoryRoot 'bootstrap/main.tf') -Raw
  $bootstrapFiles = Get-Content -LiteralPath (Join-Path $repositoryRoot 'bootstrap/files.tf') -Raw
  $bootstrapVariables = Get-Content -LiteralPath (Join-Path $repositoryRoot 'bootstrap/variables.tf') -Raw
  $bootstrapOutputs = Get-Content -LiteralPath (Join-Path $repositoryRoot 'bootstrap/outputs.tf') -Raw
  $bootstrapMigrations = Get-Content -LiteralPath (Join-Path $repositoryRoot 'bootstrap/migrations.tf') -Raw
  $codeownersTemplate = Get-Content -LiteralPath (Join-Path $repositoryRoot 'bootstrap/templates/CODEOWNERS.tftpl') -Raw
  $bootstrapScript = Get-Content -LiteralPath $legacyBootstrapPath -Raw
  $prValidateWorkflow = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/pr-validate.yml') -Raw
  $applyWorkflow = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/apply.yml') -Raw
  $terraformOnlyCount = 'count\s*=\s*var\.starter_name\s*==\s*"terraform"\s*\?\s*1\s*:\s*0'

  Assert-Equal 6 ([regex]::Matches($bootstrapMain, $terraformOnlyCount).Count) 'Every Terraform state resource and backend variable must be conditional.'
  Assert-Matches $bootstrapMain "(?s)data `"azurerm_storage_account`" `"state`".*?$terraformOnlyCount" 'State storage lookup must be Terraform-only.'
  Assert-Matches $bootstrapMain "(?s)resource `"azurerm_storage_container`" `"tfstate`".*?$terraformOnlyCount" 'State container must be Terraform-only.'
  Assert-Matches $bootstrapMain "(?s)resource `"azurerm_role_assignment`" `"state_blob_contributor`".*?$terraformOnlyCount" 'State blob RBAC must be Terraform-only.'
  Assert-Matches $bootstrapMain "(?s)resource `"github_actions_variable`" `"backend_resource_group`".*?$terraformOnlyCount" 'Backend GitHub variables must be Terraform-only.'
  Assert-Matches $bootstrapVariables '(?s)variable "state_storage_account_name".*?default\s*=\s*null.*?var\.starter_name != "terraform"' 'State storage input must be optional for Bicep.'
  Assert-Matches $bootstrapOutputs 'try\(azurerm_storage_container\.tfstate\[0\]\.name, null\)' 'Bicep state container output must be null-safe.'
  Assert-Matches $bootstrapOutputs 'pwsh \./scripts/Grant-SubscriptionCreatorRole\.ps1' 'Bootstrap output must use the accelerator billing role helper.'
  Assert-Equal $false ($bootstrapOutputs -match 'Install-Module ALZ') 'Bootstrap output must not depend on the ALZ module.'
  Assert-Equal 7 ([regex]::Matches($bootstrapMigrations, '(?m)^moved \{').Count) 'Conditional resources must preserve existing Terraform state addresses.'
  Assert-Matches $bootstrapMigrations '(?s)from = github_repository_file\.accelerator_metadata.*?to\s+= github_repository_file\.accelerator_metadata\[0\]' 'Accelerator metadata state must migrate to its handoff-gated address.'
  Assert-Matches $bootstrapMigrations '(?s)from = github_repository_file\.codeowners.*?to\s+= github_repository_file\.codeowners\[0\]' 'CODEOWNERS state must migrate to its handoff-gated address.'
  Assert-Matches $bootstrapScript "Terraform runtime state configuration is not used by the Bicep starter" 'Bicep configuration must skip Terraform runtime state prompts.'
  Assert-Matches $bootstrapScript '\$planArgs = @\(\$chdir, ''plan'', ''-input=false'', "-out=\$planPath"\)' 'Terraform plan output path must be passed as one expanded argument.'
  Assert-Matches $bootstrapFiles 'skeleton_include_patterns\s*=\s*concat\(' 'Repository seeding must use stable package roots.'
  Assert-Equal $false ($bootstrapFiles -match 'fileset\(local\.skeleton_root, "\*\*/\*"\)') 'Repository seeding must not scan mutable bootstrap state.'
  Assert-Matches $bootstrapFiles '\^bicep/main\\\\\.json\$' 'Repository seeding must exclude the compiled Bicep artifact.'
  Assert-Matches $bootstrapVariables '(?s)variable "repository_source_handoff_complete".*?default\s*=\s*false' 'Repository source handoff must be opt-in until the initial seed succeeds.'
  Assert-Equal 5 ([regex]::Matches($bootstrapFiles, 'var\.repository_source_handoff_complete').Count) 'Every seeded repository file resource must stop being declared after handoff.'
  Assert-Matches $bootstrapScript 'function Complete-RepositorySourceHandoff' 'Bootstrap must implement an explicit repository source handoff.'
  Assert-Matches $bootstrapScript '& terraform \$chdir ''state'' ''rm'' @sourceFileAddresses' 'Repository source handoff must detach seeded files from Terraform state.'
  Assert-Matches $bootstrapScript '(?s)Complete-RepositorySourceHandoff.*?\$Inputs\.repository_source_handoff_complete = \$true.*?Save-Inputs.*?Render-Tfvars' 'The handoff must persist only after seeded file resources are detached.'
  Assert-Matches $bootstrapScript '(?s)terraform apply failed.*?Complete-RepositorySourceHandoff' 'Repository source handoff must run only after a successful Terraform apply.'
  Assert-Matches $bootstrapMain 'resource "github_team_repository" "production_reviewers"' 'Production reviewer teams must receive repository access.'
  Assert-Matches $bootstrapMain 'depends_on = \[github_team_repository\.production_reviewers\]' 'Environment protection must wait for reviewer team access.'
  Assert-Matches $bootstrapMain 'can_admins_bypass\s*=\s*true' 'Repository administrators must be able to bypass a one-person environment approval deadlock.'
  Assert-Matches $bootstrapScript 'function Get-ProductionReviewerAssessment' 'Bootstrap must assess actual eligible production reviewers.'
  Assert-Matches $bootstrapScript 'teams/\$teamId/members\?per_page=100' 'Production reviewer assessment must resolve team membership.'
  Assert-Matches $bootstrapScript 'HashSet\[long\]' 'Production reviewer assessment must deduplicate users and team members.'
  Assert-Matches $bootstrapScript 'One-person setups are allowed: a repository administrator can use "Start all waiting jobs"' 'Bootstrap must explain the supported one-person admin bypass.'
  Assert-Equal 2 ([regex]::Matches($bootstrapScript, 'Write-ProductionReviewerGuardrail -Inputs \$Inputs').Count) 'Reviewer guardrail must run during configure and validate.'
  Assert-Matches $bootstrapScript 'Az CLI not signed in \(\$\(\$_\.Exception\.Message\)\)' 'Azure CLI preflight failures must preserve the underlying error.'

  $tokens = $null
  $parseErrors = $null
  $bootstrapAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $legacyBootstrapPath,
    [ref] $tokens,
    [ref] $parseErrors
  )
  Assert-Equal 0 $parseErrors.Count 'Bootstrap script must parse before reviewer functions are tested.'
  foreach ($functionName in @(
    'Get-Inputs',
    'Configure-ProductionEnv',
    'Get-ProductionReviewerAssessment',
    'Write-ProductionReviewerGuardrail',
    'Complete-RepositorySourceHandoff'
  )) {
    $functionAst = $bootstrapAst.Find(
      {
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
          $node.Name -eq $functionName
      },
      $true
    )
    Invoke-Expression $functionAst.Extent.Text
  }

  $emptyInputs = Get-Inputs -Path (Join-Path $testRoot 'missing-inputs.json')
  Assert-Equal 'Hashtable' $emptyInputs.GetType().Name 'New bootstrap inputs must use a mutable Hashtable.'
  function Set-TestInput {
    param([hashtable] $Inputs)
    $Inputs.test_value = 'preserved'
  }
  Set-TestInput -Inputs $emptyInputs
  Assert-Equal 'preserved' $emptyInputs.test_value 'Hashtable mutations must propagate across typed function boundaries.'

  $persistedInputsPath = Join-Path $testRoot 'persisted-inputs.json'
  '{"tenant_id":"test-tenant"}' | Set-Content -LiteralPath $persistedInputsPath
  $persistedInputs = Get-Inputs -Path $persistedInputsPath
  Assert-Equal 'Hashtable' $persistedInputs.GetType().Name 'Persisted bootstrap inputs must be normalized to a mutable Hashtable.'
  Set-TestInput -Inputs $persistedInputs
  Assert-Equal 'preserved' $persistedInputs.test_value 'Persisted input mutations must propagate across typed function boundaries.'
  Assert-Equal 'test-tenant' $persistedInputs.tenant_id 'Persisted input values must survive Hashtable normalization.'

  $script:handoffStateRemoveFails = $false
  $script:handoffRemovedAddresses = @()
  $script:handoffSaved = $false
  $script:handoffRendered = $false
  $script:ScriptRoot = $testRoot
  function global:terraform {
    if ($args -contains 'list') {
      $global:LASTEXITCODE = 0
      return @(
        'github_repository.this',
        'github_repository_file.accelerator_metadata[0]',
        'github_repository_file.skeleton["README.md"]',
        'github_repository_file.platform_auto_tfvars[0]',
        'github_repository_file.codeowners[0]'
      )
    }
    if ($args -contains 'rm') {
      $script:handoffRemovedAddresses = @($args | Where-Object { $_ -like 'github_repository_file.*' })
      $global:LASTEXITCODE = if ($script:handoffStateRemoveFails) { 1 } else { 0 }
      return
    }
    $global:LASTEXITCODE = 1
  }
  function Save-Inputs { $script:handoffSaved = $true }
  function Render-Tfvars { $script:handoffRendered = $true }
  function Write-Info { param([string] $Message) }
  function Write-Header { param([string] $Message) }
  function Write-Ok { param([string] $Message) }

  $handoffInputs = @{ copy_skeleton_files = $true }
  Complete-RepositorySourceHandoff -Inputs $handoffInputs -InputsPath 'inputs.json' -TfvarsPath 'terraform.tfvars.json'
  Assert-Equal $true $handoffInputs.repository_source_handoff_complete 'Successful handoff must persist the lifecycle flag.'
  Assert-Equal $false $handoffInputs.copy_skeleton_files 'Successful handoff must disable legacy skeleton seeding.'
  Assert-Equal 4 $script:handoffRemovedAddresses.Count 'Handoff must remove every seeded file address and leave unrelated state intact.'
  Assert-Equal $true $script:handoffSaved 'Successful handoff must save the bootstrap sidecar.'
  Assert-Equal $true $script:handoffRendered 'Successful handoff must render safe Terraform inputs.'

  $script:handoffStateRemoveFails = $true
  $script:handoffSaved = $false
  $script:handoffRendered = $false
  $failedHandoffInputs = @{ copy_skeleton_files = $true }
  Assert-Throws {
    Complete-RepositorySourceHandoff -Inputs $failedHandoffInputs -InputsPath 'inputs.json' -TfvarsPath 'terraform.tfvars.json'
  } '*terraform state rm failed during repository source handoff*'
  Assert-Equal $false $failedHandoffInputs.ContainsKey('repository_source_handoff_complete') 'Failed state detachment must not mark the handoff complete.'
  Assert-Equal $true $failedHandoffInputs.copy_skeleton_files 'Failed state detachment must preserve skeleton seeding configuration.'
  Assert-Equal $false $script:handoffSaved 'Failed state detachment must not save a completed handoff.'
  Assert-Equal $false $script:handoffRendered 'Failed state detachment must not render a completed handoff.'
  Remove-Item Function:\terraform
  Remove-Item Function:\Save-Inputs
  Remove-Item Function:\Render-Tfvars
  Remove-Item Function:\Write-Info
  Remove-Item Function:\Write-Header
  Remove-Item Function:\Write-Ok

  function Edit-Group { return $true }
  function Read-PromptString { return 'production' }
  function Get-GitHubNumericIds {
    param([string] $Kind, [array] $Existing)
    if ($Kind -eq 'user') {
      return 7
    }
  }
  function Write-Warn { param([string] $Message) }
  function Write-Ok { param([string] $Message) }
  function Write-Host { param([Parameter(ValueFromRemainingArguments)] $Message) }
  $singleReviewerInputs = @{}
  Configure-ProductionEnv -Inputs $singleReviewerInputs
  Assert-Equal $true $singleReviewerInputs.production_reviewer_user_ids.GetType().IsArray 'A single user reviewer ID must remain an array.'
  Assert-Equal 1 $singleReviewerInputs.production_reviewer_user_ids.Count 'A single user reviewer ID array must contain one item.'
  Assert-Equal $true $singleReviewerInputs.production_reviewer_team_ids.GetType().IsArray 'An empty team reviewer result must remain an array.'
  Assert-Equal 0 $singleReviewerInputs.production_reviewer_team_ids.Count 'An empty team reviewer array must contain no items.'
  Remove-Item Function:\Set-TestInput
  Remove-Item Function:\Edit-Group
  Remove-Item Function:\Read-PromptString
  Remove-Item Function:\Get-GitHubNumericIds
  Remove-Item Function:\Write-Host
  Remove-Item Function:\Configure-ProductionEnv
  Remove-Item Function:\Complete-RepositorySourceHandoff
  Remove-Item Function:\Get-Inputs

  $script:mockTeamMembers = @{
    '100' = @(7, 8)
    '200' = @(8)
  }
  function global:gh {
    $teamMatch = [regex]::Match(($args -join ' '), 'teams/(\d+)/members')
    $teamId = [long] $teamMatch.Groups[1].Value
    if (-not $script:mockTeamMembers.ContainsKey("$teamId")) {
      $global:LASTEXITCODE = 1
      return
    }
    $global:LASTEXITCODE = 0
    return $script:mockTeamMembers["$teamId"]
  }

  $assessment = Get-ProductionReviewerAssessment -Inputs @{
    production_reviewer_user_ids = @(7)
    production_reviewer_team_ids = @(100, 200)
  }
  Assert-Equal 2 $assessment.EligibleReviewerCount 'Reviewer assessment must deduplicate direct users and overlapping team membership.'
  Assert-Equal $true $assessment.IsComplete 'Reviewer assessment must be complete when every team lookup succeeds.'

  $failedAssessment = Get-ProductionReviewerAssessment -Inputs @{
    production_reviewer_user_ids = @()
    production_reviewer_team_ids = @(300)
  }
  Assert-Equal $false $failedAssessment.IsComplete 'Reviewer assessment must report failed team lookups.'
  Assert-Equal 300 $failedAssessment.FailedTeamIds[0] 'Reviewer assessment must identify the team that could not be resolved.'

  $script:reviewerWarning = ''
  function Write-Warn { param([string] $Message) $script:reviewerWarning = $Message }
  function Write-Ok { param([string] $Message) }
  Write-ProductionReviewerGuardrail -Inputs @{
    production_reviewer_user_ids = @(7)
    production_reviewer_team_ids = @()
  }
  Assert-Matches $script:reviewerWarning 'Start all waiting jobs' 'One eligible reviewer must produce admin bypass guidance.'

  Remove-Item Function:\Get-ProductionReviewerAssessment -ErrorAction SilentlyContinue
  Remove-Item Function:\Write-ProductionReviewerGuardrail -ErrorAction SilentlyContinue
  Remove-Item Function:\Write-Warn -ErrorAction SilentlyContinue
  Remove-Item Function:\Write-Ok -ErrorAction SilentlyContinue
  Remove-Item Function:\global:gh -ErrorAction SilentlyContinue

  Assert-Matches $bootstrapMain 'repo:\$\{var\.github_owner\}@\$\{var\.github_owner_id\}/\$\{var\.github_repository_name\}@\$\{local\.github_repository_numeric_id\}' 'Immutable GitHub OIDC subjects must include owner and repository IDs.'
  Assert-Matches $bootstrapMain '(?s)resource "azurerm_role_assignment" "mg_contributor".*?role_definition_name\s*=\s*"Contributor"' 'The pipeline identity must be able to run management-group deployments.'
  Assert-Matches $bootstrapVariables 'variable "github_oidc_subject_mode"' 'Bootstrap variables must expose GitHub OIDC subject mode.'
  Assert-Matches $bootstrapVariables 'github_owner_id is required when github_oidc_subject_mode is immutable' 'Immutable OIDC subjects must require the numeric owner ID.'
  Assert-Matches $bootstrapScript "Choices @\('standard', 'immutable'\)" 'The bootstrap wizard must support immutable GitHub OIDC subjects.'
  Assert-Matches $bootstrapScript "-MinVersion '1\.10\.0'" 'Bootstrap preflight must accept the AVM module minimum Terraform version.'
  Assert-Matches $bootstrapScript "-MaxVersionExclusive '2\.0\.0'" 'Bootstrap preflight must allow newer Terraform 1.x releases.'
  $bootstrapTerraform = Get-Content -LiteralPath (Join-Path $repositoryRoot 'bootstrap/terraform.tf') -Raw
  Assert-Matches $bootstrapTerraform 'required_version\s*=\s*">= 1\.10\.0, < 2\.0\.0"' 'Bootstrap Terraform version range is incorrect.'
  Assert-Matches $bootstrapTerraform 'source\s*=\s*"hashicorp/azurerm"\s*version\s*=\s*"5\.6\.0"' 'Bootstrap AzureRM provider pin is incorrect.'
  $runtimeVersions = Get-Content -LiteralPath (Join-Path $repositoryRoot 'terraform/versions.tf') -Raw
  $runtimeLocals = Get-Content -LiteralPath (Join-Path $repositoryRoot 'terraform/locals.tf') -Raw
  Assert-Matches $runtimeVersions 'required_version\s*=\s*">= 1\.10\.0, < 2\.0\.0"' 'Runtime Terraform version range is incorrect.'
  Assert-Matches $runtimeVersions 'azapi\s*=\s*\{ source = "Azure/azapi", version = "2\.12\.0" \}' 'Runtime AzAPI must satisfy the AVM subscription-vending module constraints.'
  Assert-Matches $runtimeLocals 'name\s*=\s*try\(subnet\.name,\s*subnet_name\)' 'Terraform subnet inputs must derive the AVM-required name from the request map key.'
  Assert-Matches $runtimeLocals 'default_outbound_access_enabled\s*=\s*subnet\.default_outbound_access' 'Terraform subnet inputs must normalize the shared outbound access field.'
  Assert-Matches $runtimeLocals 'definition\s*=\s*assignment\.role_definition_id_or_name' 'Terraform role assignments must normalize the shared role definition field.'
  Assert-Matches $prValidateWorkflow "if: hashFiles\('bootstrap/\*\*'\) != '' \|\| hashFiles\('terraform/\*\*'\) != ''" 'Terraform setup must run for accelerator and generated Terraform repositories.'
  Assert-Matches $prValidateWorkflow '(?s)name: Validate runtime Terraform.*?terraform init -backend=false.*?terraform validate' 'Accelerator validation must initialize and validate the runtime dependency graph.'
  Assert-Matches $prValidateWorkflow "needs\.accelerator-validate\.outputs\.sources-available != 'true'" 'PR runtime previews must skip the accelerator source repository.'
  Assert-Matches $prValidateWorkflow "INCLUDE_SHARED_CHANGES: 'true'" 'PR previews must include every request affected by shared changes.'
  Assert-Matches $applyWorkflow 'Accelerator source repository detected; skipping runtime apply\.' 'Apply must skip sample subscriptions in the accelerator source repository.'
  Assert-Matches $applyWorkflow "INCLUDE_SHARED_CHANGES: \$\{\{ github\.event_name == 'push' && 'false' \|\| 'true' \}\}" 'Push applies must exclude shared changes while manual discovery retains them.'
  Assert-Matches $applyWorkflow 'Shared change merged without automatic deployment' 'Shared merges must explain the explicit deployment step.'
  Assert-Matches $applyWorkflow 'with \*\*mode = all\*\*' 'Shared merge guidance must direct operators to an explicit fleet deployment.'
  Assert-Matches $prValidateWorkflow "deployment_name=`"`\$\(printf 'vend-%s' '\$\{\{ matrix\.name \}\}' \| cut -c1-64\)`"" 'Bicep preview must use a stable per-subscription deployment name.'
  Assert-Matches $applyWorkflow "deployment_name=`"`\$\(printf 'vend-%s' '\$\{\{ matrix\.name \}\}' \| cut -c1-64\)`"" 'Bicep apply must use a stable per-subscription deployment name.'
  Assert-Equal $false ($prValidateWorkflow -match "deployment_name=.*github\.run_id") 'Bicep preview deployment names must not depend on the workflow run ID.'
  Assert-Equal $false ($applyWorkflow -match "deployment_name=.*github\.run_id") 'Bicep apply deployment names must not depend on the workflow run ID.'
  Assert-Matches $applyWorkflow 'az deployment mg create(?s).*?--no-wait' 'Bicep apply must start asynchronously so workflow progress can be reported.'
  Assert-Matches $applyWorkflow 'Deployment state: \$\{provisioning_state\}\. Elapsed: \$\{elapsed\}s\.' 'Bicep apply must report deployment progress.'
  Assert-Equal 2 ([regex]::Matches($applyWorkflow, '## Subscription vending result').Count) 'Both runtime engines must publish a deployment summary.'
  Assert-Matches $applyWorkflow 'terraform output -json > vending-outputs\.json' 'Terraform apply must capture structured outputs.'
  Assert-Matches $applyWorkflow '\.subscription_resource_id\.value' 'Terraform summary must publish the subscription resource ID.'
  Assert-Matches $applyWorkflow '\.effective_tags\.value' 'Terraform summary must publish effective tags.'
  Assert-Matches $applyWorkflow '\.properties\.outputs\.subscriptionId\.value' 'Bicep summary must publish the subscription ID.'
  Assert-Matches $applyWorkflow 'BICEP_DEPLOYMENT_ELAPSED_SECONDS' 'Bicep summary must publish elapsed deployment time.'
  Assert-Matches $bootstrapFiles 'starter_name\s*=\s*var\.starter_name' 'CODEOWNERS rendering must receive the selected starter.'
  Assert-Matches $bootstrapFiles 'file\s*=\s*"\.accelerator/metadata\.json"' 'Bootstrap must record generated-repository accelerator metadata.'
  Assert-Matches $bootstrapFiles 'acceleratorVersion\s*=\s*local\.accelerator_manifest\.version' 'Generated metadata must record the accelerator release.'
  Assert-Matches $bootstrapFiles 'managedFiles\s*=\s*\{' 'Generated metadata must record managed-file hashes.'
  Assert-Matches $bootstrapFiles 'f => sha256\(replace\(file\(' 'Managed-file metadata must hash normalized seeded text.'
  Assert-Matches $bootstrapFiles '(?s)resource "github_repository_file" "accelerator_metadata".*?ignore_changes\s*=\s*\[content\]' 'Bootstrap must not overwrite upgrade-owned version metadata after handoff.'
  Assert-Matches $codeownersTemplate '%\{ if starter_name == "terraform" ~\}' 'CODEOWNERS must select the Terraform runtime path conditionally.'
  Assert-Matches $codeownersTemplate '/bicep/' 'CODEOWNERS must protect the Bicep runtime path.'
  Assert-Equal $false ($codeownersTemplate -match '/bootstrap/') 'Generated CODEOWNERS must not reference accelerator-only bootstrap files.'

  $invalidStarterRoot = Join-Path $testRoot 'invalid-starters'
  Copy-Item -LiteralPath $starterRoot -Destination $invalidStarterRoot -Recurse
  $invalidManifestPath = Join-Path $invalidStarterRoot 'terraform/starter.json'
  $invalidManifest = Get-Content -LiteralPath $invalidManifestPath -Raw | ConvertFrom-Json
  $invalidManifest.capabilities.implemented = @(
    $invalidManifest.capabilities.implemented |
      Where-Object { $_ -ne 'optional-spoke-networking' }
  )
  $invalidManifest.capabilities.planned = @('optional-spoke-networking')
  $invalidManifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $invalidManifestPath

  Assert-Throws `
    -Script { Test-SubscriptionVendingStarter -Engine Terraform -StarterRoot $invalidStarterRoot } `
    -MessagePattern '*unimplemented required capabilities: optional-spoke-networking*'

  Initialize-SubscriptionVending `
    -Engine Terraform `
    -Phase configure `
    -StarterRoot $testStarterRoot `
    -NonInteractive `
    -PlanOnly `
    -InputsPath 'inputs.json'

  $captured = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
  Assert-Equal 'configure' $captured.Phase 'Phase was not forwarded.'
  Assert-Equal 'Terraform' $captured.Engine 'Engine was not forwarded.'
  Assert-Equal $testStarterRoot $captured.StarterRoot 'StarterRoot was not forwarded.'
  Assert-Equal $true $captured.NonInteractive 'NonInteractive was not forwarded.'
  Assert-Equal $true $captured.PlanOnly 'PlanOnly was not forwarded.'
  Assert-Equal 'inputs.json' $captured.InputsPath 'InputsPath was not forwarded.'
  Assert-Equal $true $captured.strict_mode_allows_missing_key 'The module must isolate the legacy bootstrap from its strict-mode scope.'

  Initialize-SubscriptionVending `
    -Engine Bicep `
    -Phase configure `
    -StarterRoot $testStarterRoot `
    -NonInteractive `
    -PlanOnly `
    -InputsPath 'bicep-inputs.json'

  $captured = Get-Content -LiteralPath $capturePath -Raw | ConvertFrom-Json
  Assert-Equal 'configure' $captured.Phase 'Bicep phase was not forwarded.'
  Assert-Equal 'Bicep' $captured.Engine 'Bicep engine was not forwarded.'
  Assert-Equal $true $captured.NonInteractive 'Bicep NonInteractive was not forwarded.'
  Assert-Equal $true $captured.PlanOnly 'Bicep PlanOnly was not forwarded.'
  Assert-Equal 'bicep-inputs.json' $captured.InputsPath 'Bicep InputsPath was not forwarded.'

  $newInputsPath = Join-Path $testRoot 'new-inputs.json'
  '{}' | Set-Content -LiteralPath $newInputsPath
  & pwsh -NoLogo -NoProfile -File $legacyBootstrapPath `
    -Engine Terraform `
    -Phase configure `
    -NonInteractive `
    -SkipPreflight `
    -InputsPath $newInputsPath `
    -TfvarsPath (Join-Path $testRoot 'new.tfvars.json') | Out-Null
  Assert-Equal 0 $LASTEXITCODE 'Legacy bootstrap should accept the Terraform starter.'
  $savedInputs = Get-Content -LiteralPath $newInputsPath -Raw | ConvertFrom-Json
  Assert-Equal 'terraform' $savedInputs.starter_name 'Legacy bootstrap did not persist the normalized starter name.'

  $newBicepInputsPath = Join-Path $testRoot 'new-bicep-inputs.json'
  '{}' | Set-Content -LiteralPath $newBicepInputsPath
  & pwsh -NoLogo -NoProfile -File $legacyBootstrapPath `
    -Engine Bicep `
    -Phase configure `
    -NonInteractive `
    -SkipPreflight `
    -InputsPath $newBicepInputsPath `
    -TfvarsPath (Join-Path $testRoot 'new-bicep.tfvars.json') | Out-Null
  Assert-Equal 0 $LASTEXITCODE 'Legacy bootstrap should accept the Bicep starter.'
  $savedBicepInputs = Get-Content -LiteralPath $newBicepInputsPath -Raw | ConvertFrom-Json
  Assert-Equal 'bicep' $savedBicepInputs.starter_name 'Legacy bootstrap did not persist the normalized Bicep starter name.'

  $mismatchInputsPath = Join-Path $testRoot 'mismatch-inputs.json'
  '{"starter_name":"terraform"}' | Set-Content -LiteralPath $mismatchInputsPath
  $mismatchOutput = & pwsh -NoLogo -NoProfile -File $legacyBootstrapPath `
    -Engine Bicep `
    -Phase configure `
    -InputsPath $mismatchInputsPath `
    -TfvarsPath (Join-Path $testRoot 'mismatch.tfvars.json') 2>&1
  Assert-Equal 1 $LASTEXITCODE 'Legacy bootstrap must reject changing an existing starter.'
  Assert-Equal $true (($mismatchOutput | Out-String) -like "*saved bootstrap uses starter 'terraform'*") 'Starter mismatch error was not reported.'
  $global:LASTEXITCODE = 0

  Assert-Throws `
    -Script { Test-SubscriptionVendingConfiguration -InputsPath (Join-Path $testRoot 'missing.json') -BootstrapPath $bootstrapPath } `
    -MessagePattern '*Configuration file not found*'

  @'
param(
  [string] $Engine,
  [string] $StarterRoot,
  [string] $Phase,
  [string] $ScriptRoot,
  [switch] $NonInteractive,
  [switch] $AutoApprove,
  [switch] $PlanOnly,
  [switch] $Reconfigure,
  [switch] $SkipPreflight,
  [string] $InputsPath,
  [string] $TfvarsPath
)
exit 9
'@ | Set-Content -LiteralPath (Join-Path $bootstrapPath 'Invoke-Bootstrap.ps1')

  Assert-Throws `
    -Script {
      Initialize-SubscriptionVending `
        -Engine Terraform `
        -Phase configure `
        -StarterRoot $testStarterRoot `
        -NonInteractive
    } `
    -MessagePattern '*Terraform bootstrap exited with code 9*'

  $missingPathStarterRoot = Join-Path $testRoot 'missing-path-starters'
  Copy-Item -LiteralPath $starterRoot -Destination $missingPathStarterRoot -Recurse
  $missingPathManifest = Join-Path $missingPathStarterRoot 'terraform/starter.json'
  $manifest = Get-Content -LiteralPath $missingPathManifest -Raw | ConvertFrom-Json
  $manifest.runtime.enginePath = 'missing-engine'
  $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $missingPathManifest

  Assert-Throws `
    -Script { Test-SubscriptionVendingStarter -Engine Terraform -StarterRoot $missingPathStarterRoot } `
    -MessagePattern '*requires missing directory*'

  & pwsh -NoLogo -NoProfile -File $legacyBootstrapPath -Phase configure -WhatIf 2>$null
  Assert-Equal 1 $LASTEXITCODE 'Legacy bootstrap must reject unsafe WhatIf usage in bootstrap mode.'
  $global:LASTEXITCODE = 0

  Write-Host 'SubscriptionVending module tests passed.' -ForegroundColor Green
}
finally {
  Remove-Module SubscriptionVending -ErrorAction SilentlyContinue
  Remove-Item Env:SUBSCRIPTION_VENDING_TEST_CAPTURE -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
