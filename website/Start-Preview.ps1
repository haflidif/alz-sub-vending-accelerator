#Requires -Version 7.2

[CmdletBinding()]
param(
  [string] $HugoPath = 'hugo',

  [Parameter(ValueFromRemainingArguments)]
  [string[]] $HugoArguments
)

$ErrorActionPreference = 'Stop'
$requiredVersion = [version] '0.167.0'
$hugoCommand = Get-Command -Name $HugoPath -ErrorAction SilentlyContinue

if (-not $hugoCommand) {
  throw @"
Hugo Extended $requiredVersion or newer is required but was not found.
Install it with:
  winget install --id Hugo.Hugo.Extended --exact --source winget
"@
}

$versionOutput = (& $hugoCommand.Source version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch 'hugo v(?<Version>\d+\.\d+\.\d+)') {
  throw "Unable to determine the Hugo version from: $versionOutput"
}

$installedVersion = [version] $Matches.Version
if ($installedVersion -lt $requiredVersion -or $versionOutput -notmatch '\+extended') {
  throw @"
Hugo Extended $requiredVersion or newer is required. Found: $versionOutput
Install or upgrade it with:
  winget install --id Hugo.Hugo.Extended --exact --source winget
Then restart the terminal and run:
  Get-Command hugo -All
"@
}

& (Join-Path $PSScriptRoot 'Install-Theme.ps1')
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& $hugoCommand.Source server `
  --source $PSScriptRoot `
  --baseURL 'http://localhost:1313/' `
  --disableFastRender `
  @HugoArguments
