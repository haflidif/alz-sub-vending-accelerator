$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$modulePath = Join-Path $repositoryRoot 'bicep/SubscriptionVending.Bicep.psm1'
$templatePath = Join-Path $repositoryRoot 'bicep/main.bicep'

function Assert-Equal {
  param($Expected, $Actual, [string] $Message)
  if ($Expected -ne $Actual) {
    throw "$Message Expected '$Expected', got '$Actual'."
  }
}

function Assert-Throws {
  param([scriptblock] $Script, [string] $MessagePattern)
  try {
    & $Script
  }
  catch {
    if ($_.Exception.Message -like $MessagePattern) {
      return
    }
    throw "Expected error matching '$MessagePattern', got '$($_.Exception.Message)'."
  }
  throw "Expected error matching '$MessagePattern', but no error was thrown."
}

Import-Module $modulePath -Force
try {
  $template = Get-Content -LiteralPath $templatePath -Raw
  Assert-Equal $true ($template -match "param existingSubscriptionId string = ''") 'Existing-subscription validation input is missing.'
  Assert-Equal $true ($template -match 'subscriptionAliasEnabled: empty\(existingSubscriptionId\)') 'Subscription creation is not disabled for existing-subscription validation.'
  Assert-Equal $true ($template -match 'virtualNetworkName: virtualNetworkEnabled \? virtualNetworkName : null') 'Disabled networking must not pass an invalid empty VNet name.'

  $platform = @{
    billingScopes = @{
      default = '/providers/Microsoft.Billing/billingAccounts/123/enrollmentAccounts/456'
    }
    managementGroupIds = @{
      corp = '/providers/Microsoft.Management/managementGroups/contoso-corp'
      online = '/providers/Microsoft.Management/managementGroups/contoso-online'
      sandbox = '/providers/Microsoft.Management/managementGroups/contoso-sandbox'
    }
    hubNetworkResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub'
    mandatoryTags = @{
      managedby = 'bicep'
    }
    costAllocation = @{
      name = 'projectcode'
      required = $true
      pattern = '^PRJ-[0-9]+$'
    }
    enableTelemetry = $false
    resourceProviders = @{}
  }

  $request = @{
    archetype = 'corp'
    location = 'westeurope'
    owner = 'owner@example.com'
    costAllocationCode = 'PRJ-1234'
    network = @{
      enabled = $true
      hubPeering = $false
      addressSpace = @('10.20.0.0/16')
      subnets = @{
        workload = @{
          address_prefixes = @('10.20.1.0/24')
        }
      }
    }
    budget = @{
      amount = 500
      contacts = @('finance@example.com')
    }
    roleAssignments = @{
      reader = @{
        principal_id = '11111111-1111-1111-1111-111111111111'
        role_definition_id_or_name = 'Reader'
      }
    }
    managedIdentity = @{
      name = 'id-workload'
    }
  }

  $result = ConvertTo-BicepSubscriptionParameters -Request $request -Platform $platform -RequestName 'prod-corp-app-001'
  Assert-Equal 'prod-corp-app-001' $result.parameters.subscriptionAliasName.value 'Alias default is incorrect.'
  Assert-Equal 'contoso-corp' $result.parameters.subscriptionManagementGroupId.value 'Management group selection is incorrect.'
  Assert-Equal $true $result.parameters.virtualNetworkPeeringEnabled.value 'Corp guardrail must force hub peering.'
  Assert-Equal '10.20.1.0/24' $result.parameters.virtualNetworkSubnets.value[0].addressPrefix 'Subnet conversion is incorrect.'
  Assert-Equal 'PRJ-1234' $result.parameters.subscriptionTags.value.projectcode 'Cost allocation tag is missing.'
  Assert-Equal 500 $result.parameters.budgetAmount.value 'Budget amount is incorrect.'
  Assert-Equal 2 $result.parameters.budgetContactEmails.value.Count 'Budget contacts are incorrect.'
  Assert-Equal 'Reader' $result.parameters.roleAssignments.value[0].definition 'Role assignment conversion is incorrect.'
  Assert-Equal 'id-workload' $result.parameters.userAssignedManagedIdentities.value[0].name 'Managed identity conversion is incorrect.'
  Assert-Equal $false $result.parameters.enableTelemetry.value 'Telemetry setting is incorrect.'
  Assert-Equal 0 $result.parameters.resourceProviders.value.Count 'Explicit resource provider configuration was not preserved.'

  $invalidRequest = $request.Clone()
  $invalidRequest.costAllocationCode = 'INVALID'
  Assert-Throws `
    -Script { ConvertTo-BicepSubscriptionParameters -Request $invalidRequest -Platform $platform -RequestName 'invalid' } `
    -MessagePattern '*does not match the platform pattern*'

  $sandboxRequest = @{
    archetype = 'sandbox'
    location = 'westeurope'
    owner = 'owner@example.com'
    costAllocationCode = 'PRJ-1234'
  }
  Assert-Throws `
    -Script { ConvertTo-BicepSubscriptionParameters -Request $sandboxRequest -Platform $platform -RequestName 'sandbox' } `
    -MessagePattern "*requires a budget*"

  $fractionalBudgetRequest = $request.Clone()
  $fractionalBudgetRequest.budget = @{
    amount = 10.5
  }
  Assert-Throws `
    -Script { ConvertTo-BicepSubscriptionParameters -Request $fractionalBudgetRequest -Platform $platform -RequestName 'fractional-budget' } `
    -MessagePattern '*whole number*'

  Write-Host 'Bicep starter tests passed.' -ForegroundColor Green
}
finally {
  Remove-Module SubscriptionVending.Bicep -ErrorAction SilentlyContinue
}
