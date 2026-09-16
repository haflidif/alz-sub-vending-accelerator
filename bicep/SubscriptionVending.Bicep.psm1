Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-MapKey {
  param(
    [Parameter(Mandatory)]
    [System.Collections.IDictionary] $Map,

    [Parameter(Mandatory)]
    [string] $Key
  )

  return $Map.Contains($Key)
}

function Get-MapValue {
  param(
    [Parameter(Mandatory)]
    [System.Collections.IDictionary] $Map,

    [Parameter(Mandatory)]
    [string] $Key,

    $Default = $null
  )

  if (Test-MapKey -Map $Map -Key $Key) {
    return $Map[$Key]
  }

  return $Default
}

function Assert-RequestValue {
  param(
    [Parameter(Mandatory)]
    [bool] $Condition,

    [Parameter(Mandatory)]
    [string] $Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function ConvertTo-BicepSubscriptionParameters {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Collections.IDictionary] $Request,

    [Parameter(Mandatory)]
    [System.Collections.IDictionary] $Platform,

    [Parameter(Mandatory)]
    [string] $RequestName
  )

  $archetypes = @{
    corp = @{
      HubPeeringDefault = $true
      HubPeeringAllowFalse = $false
      BudgetRequired = $false
      BudgetThresholds = @(100)
    }
    online = @{
      HubPeeringDefault = $false
      HubPeeringAllowFalse = $true
      BudgetRequired = $false
      BudgetThresholds = @(100)
    }
    sandbox = @{
      HubPeeringDefault = $false
      HubPeeringAllowFalse = $true
      BudgetRequired = $true
      BudgetThresholds = @(100)
    }
  }

  $archetype = [string](Get-MapValue -Map $Request -Key 'archetype' -Default '')
  $location = [string](Get-MapValue -Map $Request -Key 'location' -Default '')
  $owner = [string](Get-MapValue -Map $Request -Key 'owner' -Default '')
  Assert-RequestValue ($archetype -ne '') "$RequestName is missing required field: archetype."
  Assert-RequestValue ($location -ne '') "$RequestName is missing required field: location."
  Assert-RequestValue ($owner -ne '') "$RequestName is missing required field: owner."
  Assert-RequestValue ($archetypes.ContainsKey($archetype)) "Unknown archetype '$archetype' in $RequestName."

  $billingScopes = Get-MapValue -Map $Platform -Key 'billingScopes'
  $managementGroupIds = Get-MapValue -Map $Platform -Key 'managementGroupIds'
  Assert-RequestValue ($billingScopes -is [System.Collections.IDictionary]) 'Platform configuration requires billingScopes.'
  Assert-RequestValue ($managementGroupIds -is [System.Collections.IDictionary]) 'Platform configuration requires managementGroupIds.'

  $billingScopeKey = [string](Get-MapValue -Map $Request -Key 'billingScopeKey' -Default 'default')
  Assert-RequestValue (Test-MapKey -Map $billingScopes -Key $billingScopeKey) "Unknown billingScopeKey '$billingScopeKey'."
  Assert-RequestValue (Test-MapKey -Map $managementGroupIds -Key $archetype) "No management group is configured for archetype '$archetype'."
  $managementGroupResourceId = [string]$managementGroupIds[$archetype]
  $managementGroupId = ($managementGroupResourceId -split '/')[-1]
  Assert-RequestValue ($managementGroupId -ne '') "The management group configured for archetype '$archetype' is invalid."

  $displayName = [string](Get-MapValue -Map $Request -Key 'displayName' -Default $RequestName)
  $aliasName = [string](Get-MapValue -Map $Request -Key 'aliasName' -Default $RequestName)
  $workload = [string](Get-MapValue -Map $Request -Key 'workload' -Default 'Production')
  Assert-RequestValue ($workload -in @('Production', 'DevTest')) "Invalid workload '$workload'."

  $technicalResponsible = [string](Get-MapValue -Map $Request -Key 'technicalResponsible' -Default $owner)
  $costCenter = [string](Get-MapValue -Map $Request -Key 'costCenter' -Default 'unassigned')
  $workloadName = [string](Get-MapValue -Map $Request -Key 'workloadName' -Default $aliasName)
  $costAllocationCode = [string](Get-MapValue -Map $Request -Key 'costAllocationCode' -Default '')
  $costAllocation = Get-MapValue -Map $Platform -Key 'costAllocation' -Default @{}
  $costAllocationKey = [string](Get-MapValue -Map $costAllocation -Key 'name' -Default 'projectcode')
  $costAllocationRequired = [bool](Get-MapValue -Map $costAllocation -Key 'required' -Default $false)
  $costAllocationPattern = Get-MapValue -Map $costAllocation -Key 'pattern'

  Assert-RequestValue (-not $costAllocationRequired -or $costAllocationCode -ne '') "costAllocationCode is required by platform policy."
  if ($costAllocationCode -ne '' -and $null -ne $costAllocationPattern -and [string]$costAllocationPattern -ne '') {
    Assert-RequestValue ($costAllocationCode -match [string]$costAllocationPattern) "costAllocationCode '$costAllocationCode' does not match the platform pattern."
  }

  $mandatoryTags = Get-MapValue -Map $Platform -Key 'mandatoryTags' -Default @{}
  $callerTags = Get-MapValue -Map $Request -Key 'tags' -Default @{}
  Assert-RequestValue ($mandatoryTags -is [System.Collections.IDictionary]) 'mandatoryTags must be an object.'
  Assert-RequestValue ($callerTags -is [System.Collections.IDictionary]) 'tags must be an object.'

  $identityTags = [ordered]@{
    businessowner = $owner
    technicalcontact = $technicalResponsible
    costcenter = $costCenter
    workloadname = $workloadName
    environment = $workload
  }
  if ($costAllocationCode -ne '') {
    $identityTags[$costAllocationKey] = $costAllocationCode
  }

  $reservedTagKeys = @($identityTags.Keys) + @($mandatoryTags.Keys) + @('archetype', $costAllocationKey)
  $collisions = @($callerTags.Keys | Where-Object { $_ -in $reservedTagKeys })
  Assert-RequestValue ($collisions.Count -eq 0) "Free-form tags contain reserved keys: $($collisions -join ', ')."

  $effectiveTags = [ordered]@{}
  foreach ($source in @($callerTags, $mandatoryTags, @{ archetype = $archetype }, $identityTags)) {
    foreach ($key in $source.Keys) {
      $effectiveTags[$key] = [string]$source[$key]
    }
  }

  $archetypeConfig = $archetypes[$archetype]
  $network = Get-MapValue -Map $Request -Key 'network' -Default @{}
  $networkEnabled = [bool](Get-MapValue -Map $network -Key 'enabled' -Default $false)
  $hubPeeringRequested = [bool](Get-MapValue -Map $network -Key 'hubPeering' -Default $archetypeConfig.HubPeeringDefault)
  $hubPeeringEnabled = if ($archetypeConfig.HubPeeringAllowFalse) { $hubPeeringRequested } else { $true }
  $addressSpace = @()
  $subnets = @()
  if ($networkEnabled) {
    $addressSpace = @(Get-MapValue -Map $network -Key 'addressSpace' -Default @())
    Assert-RequestValue ($addressSpace.Count -gt 0) 'network.addressSpace is required when networking is enabled.'

    $subnetMap = Get-MapValue -Map $network -Key 'subnets' -Default @{}
    foreach ($subnetName in $subnetMap.Keys) {
      $subnet = $subnetMap[$subnetName]
      $prefixes = @(Get-MapValue -Map $subnet -Key 'address_prefixes' -Default @())
      Assert-RequestValue ($prefixes.Count -eq 1) "Subnet '$subnetName' must declare exactly one address prefix for the Bicep starter."
      $subnets += [ordered]@{
        name = [string]$subnetName
        addressPrefix = [string]$prefixes[0]
      }
    }
  }

  $hubNetworkResourceId = [string](Get-MapValue -Map $Platform -Key 'hubNetworkResourceId' -Default '')
  Assert-RequestValue (-not ($networkEnabled -and $hubPeeringEnabled) -or $hubNetworkResourceId -ne '') 'Hub peering is required but hubNetworkResourceId is not configured.'

  $budget = Get-MapValue -Map $Request -Key 'budget'
  Assert-RequestValue (-not $archetypeConfig.BudgetRequired -or $null -ne $budget) "Archetype '$archetype' requires a budget."
  $budgetEnabled = $null -ne $budget
  $budgetAmountValue = if ($budgetEnabled) { Get-MapValue -Map $budget -Key 'amount' } else { 100 }
  Assert-RequestValue ([decimal]$budgetAmountValue -eq [math]::Truncate([decimal]$budgetAmountValue)) 'The Bicep starter requires budget.amount to be a whole number.'
  $budgetAmount = [int]$budgetAmountValue
  $budgetContacts = if ($budgetEnabled) { @($owner) + @(Get-MapValue -Map $budget -Key 'contacts' -Default @()) } else { @() }

  $roleAssignments = @()
  $requestRoleAssignments = Get-MapValue -Map $Request -Key 'roleAssignments' -Default @{}
  Assert-RequestValue ($requestRoleAssignments -is [System.Collections.IDictionary]) 'roleAssignments must be an object.'
  foreach ($assignmentName in $requestRoleAssignments.Keys) {
    $assignment = $requestRoleAssignments[$assignmentName]
    $roleAssignments += [ordered]@{
      principalId = [string](Get-MapValue -Map $assignment -Key 'principal_id')
      definition = [string](Get-MapValue -Map $assignment -Key 'role_definition_id_or_name')
      relativeScope = ''
    }
  }

  $managedIdentity = Get-MapValue -Map $Request -Key 'managedIdentity'
  $managedIdentityResourceGroupName = ''
  $managedIdentities = @()
  if ($null -ne $managedIdentity) {
    $managedIdentityResourceGroupName = [string](Get-MapValue -Map $managedIdentity -Key 'resourceGroupName' -Default "rg-$aliasName-identity")
    $managedIdentityName = [string](Get-MapValue -Map $managedIdentity -Key 'name' -Default '')
    Assert-RequestValue ($managedIdentityName -ne '') 'managedIdentity.name is required.'
    $managedIdentities = @(
      [ordered]@{
        name = $managedIdentityName
        roleAssignments = @()
      }
    )
  }

  $parameters = [ordered]@{
    subscriptionAliasName = @{ value = $aliasName }
    subscriptionDisplayName = @{ value = $displayName }
    subscriptionBillingScope = @{ value = [string]$billingScopes[$billingScopeKey] }
    subscriptionWorkload = @{ value = $workload }
    subscriptionManagementGroupId = @{ value = $managementGroupId }
    subscriptionTags = @{ value = $effectiveTags }
    virtualNetworkEnabled = @{ value = $networkEnabled }
    virtualNetworkResourceGroupName = @{ value = if ($networkEnabled) { "rg-$aliasName-network" } else { '' } }
    virtualNetworkLocation = @{ value = $location }
    virtualNetworkName = @{ value = if ($networkEnabled) { "vnet-$aliasName" } else { '' } }
    virtualNetworkAddressSpace = @{ value = $addressSpace }
    virtualNetworkSubnets = @{ value = $subnets }
    virtualNetworkPeeringEnabled = @{ value = ($networkEnabled -and $hubPeeringEnabled) }
    hubNetworkResourceId = @{ value = if ($networkEnabled -and $hubPeeringEnabled) { $hubNetworkResourceId } else { '' } }
    roleAssignments = @{ value = $roleAssignments }
    userAssignedIdentityResourceGroupName = @{ value = $managedIdentityResourceGroupName }
    userAssignedManagedIdentities = @{ value = $managedIdentities }
    budgetEnabled = @{ value = $budgetEnabled }
    budgetName = @{ value = if ($budgetEnabled) { "$aliasName-monthly" } else { '' } }
    budgetAmount = @{ value = $budgetAmount }
    budgetContactEmails = @{ value = $budgetContacts }
    budgetThresholds = @{ value = @($archetypeConfig.BudgetThresholds) }
    budgetThresholdType = @{ value = 'Forecasted' }
    enableTelemetry = @{ value = [bool](Get-MapValue -Map $Platform -Key 'enableTelemetry' -Default $true) }
  }
  if (Test-MapKey -Map $Platform -Key 'resourceProviders') {
    $resourceProviders = $Platform['resourceProviders']
    Assert-RequestValue ($resourceProviders -is [System.Collections.IDictionary]) 'resourceProviders must be an object.'
    $parameters['resourceProviders'] = @{ value = $resourceProviders }
  }

  return [ordered]@{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = $parameters
  }
}

function New-BicepSubscriptionParameters {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $RequestPath,

    [Parameter(Mandatory)]
    [string] $PlatformPath,

    [Parameter(Mandatory)]
    [string] $OutputPath
  )

  if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) {
    throw "Request file not found at '$RequestPath'."
  }
  if (-not (Test-Path -LiteralPath $PlatformPath -PathType Leaf)) {
    throw "Platform configuration not found at '$PlatformPath'."
  }
  if (-not (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue)) {
    throw "ConvertFrom-Yaml is required. Install powershell-yaml before compiling subscription requests."
  }

  $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Yaml -Ordered
  $platform = Get-Content -LiteralPath $PlatformPath -Raw | ConvertFrom-Json -AsHashtable -Depth 32
  $requestName = [System.IO.Path]::GetFileNameWithoutExtension($RequestPath)
  $payload = ConvertTo-BicepSubscriptionParameters -Request $request -Platform $platform -RequestName $requestName

  $directory = Split-Path -Parent $OutputPath
  if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }

  $json = $payload | ConvertTo-Json -Depth 32
  [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))
  Get-Item -LiteralPath $OutputPath
}

Export-ModuleMember -Function @(
  'ConvertTo-BicepSubscriptionParameters'
  'New-BicepSubscriptionParameters'
)
