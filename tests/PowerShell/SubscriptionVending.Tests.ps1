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

try {
  New-Item -ItemType Directory -Path $bootstrapPath -Force | Out-Null
  Copy-Item -LiteralPath $starterRoot -Destination $testStarterRoot -Recurse
  New-Item -ItemType Directory -Path (Join-Path $testRoot 'terraform') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $testRoot 'landingzones') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $testRoot '.github/workflows') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $testRoot '.github/scripts') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $testRoot 'landingzones/sub.schema.json') -Value '{}'
  Set-Content -LiteralPath (Join-Path $testRoot '.github/workflows/pr-validate.yml') -Value 'name: test'
  Set-Content -LiteralPath (Join-Path $testRoot '.github/workflows/apply.yml') -Value 'name: test'
  Set-Content -LiteralPath (Join-Path $testRoot '.github/scripts/discover-subs.sh') -Value '# test'
  @'
param(
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
$PSBoundParameters | ConvertTo-Json | Set-Content -LiteralPath $env:SUBSCRIPTION_VENDING_TEST_CAPTURE
'@ | Set-Content -LiteralPath (Join-Path $bootstrapPath 'Invoke-Bootstrap.ps1')

  $env:SUBSCRIPTION_VENDING_TEST_CAPTURE = $capturePath
  Import-Module $modulePath -Force

  $commands = @(Get-Command -Module SubscriptionVending | Select-Object -ExpandProperty Name)
  Assert-Equal 4 $commands.Count 'Unexpected exported command count.'
  Assert-Equal $false (Get-Command Initialize-SubscriptionVending).Parameters.ContainsKey('WhatIf') 'Initialize must not expose unsafe WhatIf behavior.'

  $engines = @(Get-SubscriptionVendingEngine)
  Assert-Equal 'Available' ($engines | Where-Object Name -eq 'Terraform').Availability 'Terraform availability is incorrect.'
  Assert-Equal 'Planned' ($engines | Where-Object Name -eq 'Bicep').Availability 'Bicep availability is incorrect.'
  Assert-Equal '1.0' ($engines | Where-Object Name -eq 'Terraform').ContractVersion 'Terraform contract version is incorrect.'

  $starterResults = @(Test-SubscriptionVendingStarter)
  Assert-Equal 2 $starterResults.Count 'Unexpected starter validation result count.'
  Assert-Equal 26 ($starterResults | Where-Object Name -eq 'Terraform').ImplementedCapabilities 'Terraform capability count is incorrect.'
  Assert-Equal 0 ($starterResults | Where-Object Name -eq 'Bicep').ImplementedCapabilities 'Bicep should not report implemented capabilities yet.'

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
  Assert-Equal $true $captured.NonInteractive 'NonInteractive was not forwarded.'
  Assert-Equal $true $captured.PlanOnly 'PlanOnly was not forwarded.'
  Assert-Equal 'inputs.json' $captured.InputsPath 'InputsPath was not forwarded.'

  Assert-Throws `
    -Script { Initialize-SubscriptionVending -Engine Bicep -StarterRoot $testStarterRoot } `
    -MessagePattern '*Bicep starter is planned and cannot be selected*'

  Assert-Throws `
    -Script { Test-SubscriptionVendingConfiguration -InputsPath (Join-Path $testRoot 'missing.json') -BootstrapPath $bootstrapPath } `
    -MessagePattern '*Configuration file not found*'

  @'
param(
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
