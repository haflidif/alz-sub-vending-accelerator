Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DefaultBootstrapPath {
  $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  Join-Path $repositoryRoot 'bootstrap'
}

function Get-DefaultStarterRoot {
  $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  Join-Path $repositoryRoot 'starters'
}

function Get-StarterContract {
  param(
    [Parameter(Mandatory)]
    [string] $StarterRoot
  )

  $contractPath = Join-Path $StarterRoot 'starter-contract.json'
  if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    throw "Starter contract not found at '$contractPath'."
  }

  Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
}

function Get-StarterManifest {
  param(
    [Parameter(Mandatory)]
    [string] $StarterRoot,

    [Parameter(Mandatory)]
    [string] $Name
  )

  $manifestPath = Join-Path $StarterRoot "$($Name.ToLowerInvariant())/starter.json"
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Starter manifest not found at '$manifestPath'."
  }

  Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Resolve-StarterAssetPath {
  param(
    [Parameter(Mandatory)]
    [string] $StarterRoot,

    [Parameter(Mandatory)]
    [string] $RelativePath
  )

  if ([System.IO.Path]::IsPathRooted($RelativePath)) {
    throw "Starter asset path must be relative: '$RelativePath'."
  }

  $repositoryRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $StarterRoot))
  $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $RelativePath))
  $repositoryPrefix = $repositoryRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar

  if (-not $resolvedPath.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Starter asset path escapes the repository root: '$RelativePath'."
  }

  $resolvedPath
}

function Assert-SupportedEngine {
  param(
    [Parameter(Mandatory)]
    [ValidateSet('Terraform', 'Bicep')]
    [string] $Engine,

    [Parameter(Mandatory)]
    [string] $StarterRoot
  )

  $starter = Get-StarterManifest -StarterRoot $StarterRoot -Name $Engine
  if ($starter.availability -ne 'Available') {
    throw "The $($starter.displayName) starter is $($starter.availability.ToLowerInvariant()) and cannot be selected."
  }
}

function Invoke-LegacyTerraformBootstrap {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $ScriptPath,

    [Parameter(Mandatory)]
    [ValidateSet('Terraform', 'Bicep')]
    [string] $Engine,

    [Parameter(Mandatory)]
    [string] $StarterRoot,

    [Parameter(Mandatory)]
    [ValidateSet('preflight', 'configure', 'validate', 'terraform', 'all')]
    [string] $Phase,

    [switch] $NonInteractive,
    [switch] $AutoApprove,
    [switch] $PlanOnly,
    [switch] $Reconfigure,
    [switch] $SkipPreflight,
    [string] $InputsPath,
    [string] $TfvarsPath
  )

  if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Terraform bootstrap entry point not found at '$ScriptPath'."
  }

  $scriptParameters = @{
    Engine = $Engine
    StarterRoot = $StarterRoot
    Phase = $Phase
    ScriptRoot = Split-Path -Parent $ScriptPath
  }
  foreach ($switchName in @('NonInteractive', 'AutoApprove', 'PlanOnly', 'Reconfigure', 'SkipPreflight')) {
    if (Get-Variable -Name $switchName -ValueOnly) {
      $scriptParameters[$switchName] = $true
    }
  }
  if ($InputsPath) {
    $scriptParameters.InputsPath = $InputsPath
  }
  if ($TfvarsPath) {
    $scriptParameters.TfvarsPath = $TfvarsPath
  }

  $global:LASTEXITCODE = 0
  & {
    Set-StrictMode -Off
    & $ScriptPath @scriptParameters
  }
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "$Engine bootstrap exited with code $exitCode."
  }
}

function Get-SubscriptionVendingEngine {
  [CmdletBinding()]
  param(
    [string] $StarterRoot = (Get-DefaultStarterRoot)
  )

  Get-ChildItem -LiteralPath $StarterRoot -Directory |
    ForEach-Object {
      $manifestPath = Join-Path $_.FullName 'starter.json'
      if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        [pscustomobject]@{
          Name = $manifest.displayName
          Availability = $manifest.availability
          Starter = $manifest.name
          ContractVersion = $manifest.schemaVersion
          PreviewMode = $manifest.runtime.previewMode
          DeploymentMode = $manifest.runtime.deploymentMode
          Description = $manifest.description
        }
      }
    } |
    Sort-Object Name -Descending
}

function Test-SubscriptionVendingStarter {
  [CmdletBinding()]
  param(
    [ValidateSet('Terraform', 'Bicep')]
    [string] $Engine,

    [string] $StarterRoot = (Get-DefaultStarterRoot)
  )

  $contract = Get-StarterContract -StarterRoot $StarterRoot
  $names = if ($Engine) {
    @($Engine)
  }
  else {
    @(Get-ChildItem -LiteralPath $StarterRoot -Directory | Select-Object -ExpandProperty Name)
  }

  foreach ($name in $names) {
    $manifestPath = Join-Path $StarterRoot "$($name.ToLowerInvariant())/starter.json"
    $schemaPath = Join-Path $StarterRoot 'starter.schema.json'
    $manifestJson = Get-Content -LiteralPath $manifestPath -Raw
    if (-not ($manifestJson | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
      throw "Starter manifest '$manifestPath' does not match '$schemaPath'."
    }

    $starter = Get-StarterManifest -StarterRoot $StarterRoot -Name $name
    if ($starter.schemaVersion -ne $contract.schemaVersion) {
      throw "Starter '$($starter.name)' uses contract version '$($starter.schemaVersion)', expected '$($contract.schemaVersion)'."
    }

    $packageRoots = @($contract.packageRoots)
    $invalidPackageRoots = @(
      $packageRoots |
        Where-Object { $_ -notmatch '^[a-z][a-z0-9-]*/$' }
    )
    if ($packageRoots.Count -eq 0 -or $invalidPackageRoots.Count -gt 0) {
      throw "Starter contract contains invalid package roots: $($invalidPackageRoots -join ', ')."
    }
    if (@($packageRoots | Sort-Object -Unique).Count -ne $packageRoots.Count) {
      throw 'Starter contract package roots must be unique.'
    }

    $allCapabilities = @(
      $starter.capabilities.implemented
      $starter.capabilities.planned
      $starter.capabilities.unsupported
    )
    $duplicates = @($allCapabilities | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
      throw "Starter '$($starter.name)' declares capabilities in multiple states: $($duplicates.Name -join ', ')."
    }

    $declared = @($allCapabilities | Sort-Object -Unique)
    $missing = @($contract.requiredCapabilities | Where-Object { $_ -notin $declared })
    if ($missing.Count -gt 0) {
      throw "Starter '$($starter.name)' does not declare required capabilities: $($missing -join ', ')."
    }

    $unknownPackageRoots = @(
      $starter.package.includePrefixes |
        Where-Object { $_ -notin $contract.packageRoots }
    )
    if ($unknownPackageRoots.Count -gt 0) {
      throw "Starter '$($starter.name)' declares unknown package roots: $($unknownPackageRoots -join ', ')."
    }

    if ($starter.availability -eq 'Available') {
      $notImplemented = @($contract.requiredCapabilities | Where-Object { $_ -notin $starter.capabilities.implemented })
      if ($notImplemented.Count -gt 0) {
        throw "Available starter '$($starter.name)' has unimplemented required capabilities: $($notImplemented -join ', ')."
      }

      $requiredFiles = @(
        $starter.bootstrap.entryPoint
        $starter.runtime.requestSchemaPath
        $starter.runtime.previewWorkflowPath
        $starter.runtime.deploymentWorkflowPath
        $starter.runtime.discoveryScriptPath
      )
      foreach ($relativePath in $requiredFiles) {
        $resolvedPath = Resolve-StarterAssetPath -StarterRoot $StarterRoot -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
          throw "Available starter '$($starter.name)' requires missing file '$relativePath'."
        }
      }

      foreach ($relativePath in @($starter.runtime.enginePath, $starter.runtime.requestPath)) {
        $resolvedPath = Resolve-StarterAssetPath -StarterRoot $StarterRoot -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
          throw "Available starter '$($starter.name)' requires missing directory '$relativePath'."
        }
      }

      $enginePrefix = "$($starter.runtime.enginePath)/"
      if ($enginePrefix -notin $starter.package.includePrefixes) {
        throw "Available starter '$($starter.name)' package does not include its engine path '$enginePrefix'."
      }
    }

    [pscustomobject]@{
      Name = $starter.displayName
      Availability = $starter.availability
      ContractVersion = $starter.schemaVersion
      RequiredCapabilities = $contract.requiredCapabilities.Count
      ImplementedCapabilities = $starter.capabilities.implemented.Count
      Valid = $true
    }
  }
}

function Initialize-SubscriptionVending {
  [CmdletBinding()]
  param(
    [ValidateSet('Terraform', 'Bicep')]
    [string] $Engine = 'Terraform',

    [ValidateSet('preflight', 'configure', 'validate', 'terraform', 'all')]
    [string] $Phase = 'all',

    [switch] $NonInteractive,
    [switch] $AutoApprove,
    [switch] $PlanOnly,
    [switch] $Reconfigure,
    [switch] $SkipPreflight,
    [string] $InputsPath,
    [string] $TfvarsPath,
    [string] $BootstrapPath = (Get-DefaultBootstrapPath),
    [string] $StarterRoot = (Get-DefaultStarterRoot)
  )

  Test-SubscriptionVendingStarter -Engine $Engine -StarterRoot $StarterRoot | Out-Null
  Assert-SupportedEngine -Engine $Engine -StarterRoot $StarterRoot
  $starter = Get-StarterManifest -StarterRoot $StarterRoot -Name $Engine
  $scriptPath = if ($PSBoundParameters.ContainsKey('BootstrapPath')) {
    Join-Path $BootstrapPath 'Invoke-Bootstrap.ps1'
  }
  else {
    Resolve-StarterAssetPath -StarterRoot $StarterRoot -RelativePath $starter.bootstrap.entryPoint
  }

  $invokeParameters = @{
    ScriptPath = $scriptPath
    Engine = $Engine
    StarterRoot = $StarterRoot
    Phase = $Phase
    NonInteractive = $NonInteractive
    AutoApprove = $AutoApprove
    PlanOnly = $PlanOnly
    Reconfigure = $Reconfigure
    SkipPreflight = $SkipPreflight
    InputsPath = $InputsPath
    TfvarsPath = $TfvarsPath
  }
  Invoke-LegacyTerraformBootstrap @invokeParameters
}

function Test-SubscriptionVendingConfiguration {
  [CmdletBinding()]
  param(
    [ValidateSet('Terraform', 'Bicep')]
    [string] $Engine = 'Terraform',

    [Parameter(Mandatory)]
    [string] $InputsPath,

    [string] $BootstrapPath = (Get-DefaultBootstrapPath),
    [string] $StarterRoot = (Get-DefaultStarterRoot),
    [switch] $SkipPreflight
  )

  Test-SubscriptionVendingStarter -Engine $Engine -StarterRoot $StarterRoot | Out-Null
  Assert-SupportedEngine -Engine $Engine -StarterRoot $StarterRoot
  $starter = Get-StarterManifest -StarterRoot $StarterRoot -Name $Engine

  if (-not (Test-Path -LiteralPath $InputsPath -PathType Leaf)) {
    throw "Configuration file not found at '$InputsPath'."
  }

  $scriptPath = if ($PSBoundParameters.ContainsKey('BootstrapPath')) {
    Join-Path $BootstrapPath 'Invoke-Bootstrap.ps1'
  }
  else {
    Resolve-StarterAssetPath -StarterRoot $StarterRoot -RelativePath $starter.bootstrap.entryPoint
  }

  Invoke-LegacyTerraformBootstrap `
    -ScriptPath $scriptPath `
    -Engine $Engine `
    -StarterRoot $StarterRoot `
    -Phase validate `
    -NonInteractive `
    -SkipPreflight:$SkipPreflight `
    -InputsPath $InputsPath
}

Export-ModuleMember -Function @(
  'Get-SubscriptionVendingEngine'
  'Initialize-SubscriptionVending'
  'Test-SubscriptionVendingConfiguration'
  'Test-SubscriptionVendingStarter'
)
