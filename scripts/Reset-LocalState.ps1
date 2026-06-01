#Requires -Version 7.2
<#
.SYNOPSIS
    Wipes local operator state from the working tree (tfvars, state, caches).

.DESCRIPTION
    The working tree accumulates a few categories of local artefacts during
    iteration on an operator workstation. This script removes them in a
    well-defined order so the folder carries no tenant / subscription / billing
    IDs or other environment-specific local state.

    Categories removed (under the skeleton root, recursively):
      1. Bootstrap input state
         - terraform.tfvars
         - terraform.tfvars.json
         - .bootstrap-inputs.json
         - .bootstrap-inputs.json.bak

      2. Terraform local artefacts
         - .terraform/                (provider binaries cache)
         - .terraform.lock.hcl
         - terraform.tfstate          (only if NOT azurerm backend)
         - terraform.tfstate.backup
         - tfplan, *.tfplan, plan.txt

      3. Stray local logs and shell artefacts
         - .run.log, -? (shell-redirect leftovers)

    NEVER touched:
      * .git/                         (the working tree may itself be a git repo)
      * any *.tfvars.example file     (these ship deliberately)
      * any *.tftpl file              (bootstrap-rendered templates ship)

.PARAMETER WhatIf
    Dry-run: list what would be removed without deleting.

.PARAMETER SkipPrompt
    Skip the final confirmation prompt. Useful in CI / one-shot builds.

.PARAMETER Root
    Working-tree root directory. Defaults to the parent of this script.

.EXAMPLE
    pwsh ./scripts/Reset-LocalState.ps1 -WhatIf

.EXAMPLE
    pwsh ./scripts/Reset-LocalState.ps1 -SkipPrompt
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch] $SkipPrompt,

    [ValidateNotNullOrEmpty()]
    [string] $Root = (Resolve-Path -Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Explicit filenames (any depth) — removed verbatim. Keep this list narrow
# and additive: every entry MUST be safe to delete in any directory under
# the skeleton root.
$fileTargets = @(
    'terraform.tfvars',
    'terraform.tfvars.json',
    '.bootstrap-inputs.json',
    '.bootstrap-inputs.json.bak',
    '.terraform.lock.hcl',
    'terraform.tfstate',
    'terraform.tfstate.backup',
    'tfplan',
    'plan.txt',
    '.run.log'
)

# Glob patterns (relative to each directory under the root).
$globTargets = @(
    '*.tfplan'
)

# Directories to remove (recursively) wherever they appear.
$dirTargets = @(
    '.terraform'
)

# Hard exclusions — paths whose presence in the candidate filename means
# we MUST skip it. Used to avoid wiping the .git or shipped examples.
$excludePatterns = @(
    '\\\.git(\\|$)',
    '\.tfvars\.example$',
    '\.tftpl$'
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-Excluded {
    param([string] $Path)
    foreach ($pattern in $excludePatterns) {
        if ($Path -match $pattern) { return $true }
    }
    return $false
}

function Format-Size {
    param([long] $Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

if (-not (Test-Path -Path $Root -PathType Container)) {
    throw "Working-tree root not found: $Root"
}

$resolvedRoot = (Resolve-Path -Path $Root).Path
Write-Host ""
Write-Host "Resetting local operator state." -ForegroundColor Cyan
Write-Host "  Root: $resolvedRoot"
Write-Host ""

$victims = [System.Collections.Generic.List[object]]::new()

# Files matched by exact name
foreach ($name in $fileTargets) {
    $hits = Get-ChildItem -Path $resolvedRoot -Recurse -Force -File -Filter $name -ErrorAction SilentlyContinue
    foreach ($h in $hits) {
        if (Test-Excluded -Path $h.FullName) { continue }
        $victims.Add([pscustomobject]@{
                Type = 'file'
                Path = $h.FullName
                Size = $h.Length
            })
    }
}

# Files matched by glob
foreach ($pattern in $globTargets) {
    $hits = Get-ChildItem -Path $resolvedRoot -Recurse -Force -File -Filter $pattern -ErrorAction SilentlyContinue
    foreach ($h in $hits) {
        if (Test-Excluded -Path $h.FullName) { continue }
        $victims.Add([pscustomobject]@{
                Type = 'file'
                Path = $h.FullName
                Size = $h.Length
            })
    }
}

# Directories
foreach ($name in $dirTargets) {
    $hits = Get-ChildItem -Path $resolvedRoot -Recurse -Force -Directory -Filter $name -ErrorAction SilentlyContinue
    foreach ($h in $hits) {
        if (Test-Excluded -Path $h.FullName) { continue }
        $size = (Get-ChildItem -Path $h.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if (-not $size) { $size = 0 }
        $victims.Add([pscustomobject]@{
                Type = 'directory'
                Path = $h.FullName
                Size = $size
            })
    }
}

# Stray shell artefacts (single-char redirect leftovers like "-w")
$strays = Get-ChildItem -Path $resolvedRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^-[a-zA-Z]$' -and -not (Test-Excluded -Path $_.FullName) }
foreach ($s in $strays) {
    $victims.Add([pscustomobject]@{
            Type = 'file'
            Path = $s.FullName
            Size = $s.Length
        })
}

# Dedupe (a file under a .terraform/ dir is covered by both the dir and the file rule)
$dirPrefixes = $victims | Where-Object Type -EQ 'directory' | ForEach-Object { $_.Path + [System.IO.Path]::DirectorySeparatorChar }
$victims = $victims | Where-Object {
    if ($_.Type -eq 'directory') { return $true }
    foreach ($prefix in $dirPrefixes) {
        if ($_.Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return $true
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

if (-not $victims -or $victims.Count -eq 0) {
    Write-Host "Working tree is already clean - nothing to remove." -ForegroundColor Green
    return
}

$totalBytes = ($victims | Measure-Object -Property Size -Sum).Sum
Write-Host ("Found {0} artefact(s) totalling {1}:" -f $victims.Count, (Format-Size $totalBytes)) -ForegroundColor Yellow
Write-Host ""

$victims |
    Sort-Object -Property @{ Expression = 'Type'; Descending = $true }, Path |
    ForEach-Object {
        $rel = $_.Path.Substring($resolvedRoot.Length).TrimStart('\', '/')
        $sizeStr = Format-Size $_.Size
        $marker = if ($_.Type -eq 'directory') { '[DIR ]' } else { '[FILE]' }
        Write-Host ("  {0} {1,-10} {2}" -f $marker, $sizeStr, $rel)
    }

Write-Host ""

# ---------------------------------------------------------------------------
# Execute
# ---------------------------------------------------------------------------

if ($WhatIfPreference) {
    Write-Host "Dry run - no files were removed. Re-run without -WhatIf to delete." -ForegroundColor Cyan
    return
}

if (-not $SkipPrompt) {
    $answer = Read-Host "Delete the above artefacts? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "Aborted - no files were removed." -ForegroundColor Yellow
        return
    }
}

$removed = 0
$failed = [System.Collections.Generic.List[string]]::new()

foreach ($v in $victims) {
    try {
        if ($PSCmdlet.ShouldProcess($v.Path, 'Remove')) {
            if ($v.Type -eq 'directory') {
                Remove-Item -Path $v.Path -Recurse -Force -ErrorAction Stop
            }
            else {
                Remove-Item -Path $v.Path -Force -ErrorAction Stop
            }
            $removed++
        }
    }
    catch {
        $failed.Add(('{0}: {1}' -f $v.Path, $_.Exception.Message))
    }
}

Write-Host ""
Write-Host ("Removed {0} of {1} artefact(s)." -f $removed, $victims.Count) -ForegroundColor Green

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed to remove $($failed.Count) artefact(s):" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host ""
Write-Host "Local operator state has been reset." -ForegroundColor Green
