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
          service_endpoints = @('Microsoft.Storage')
          delegation = 'Microsoft.Web/serverFarms'
          private_endpoint_network_policies = 'NetworkSecurityGroupEnabled'
          default_outbound_access = $false
          network_security_group = @{
            name = 'nsg-workload'
            security_rules = @{
              allowHttps = @{
                access = 'Allow'
                direction = 'Inbound'
                priority = 100
                protocol = 'Tcp'
                source_address_prefix = 'VirtualNetwork'
                destination_address_prefix = '*'
                destination_port_range = '443'
                source_port_range = '*'
              }
            }
          }
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
        relative_scope = '/resourceGroups/rg-workload'
        principal_type = 'Group'
        description = 'Workload readers'
        role_assignment_condition = @{
          condition_version = '2.0'
          role_condition_type = @{
            template_name = 'constrainRoles'
            roles_to_assign = @('Reader')
          }
        }
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
  Assert-Equal '10.20.1.0/24' $result.parameters.virtualNetworkSubnets.value[0].addressPrefix 'Subnet prefix conversion is incorrect.'
  Assert-Equal 'Microsoft.Storage' $result.parameters.virtualNetworkSubnets.value[0].serviceEndpoints[0] 'Service endpoint conversion is incorrect.'
  Assert-Equal 'Microsoft.Web/serverFarms' $result.parameters.virtualNetworkSubnets.value[0].delegation 'Subnet delegation conversion is incorrect.'
  Assert-Equal 'NetworkSecurityGroupEnabled' $result.parameters.virtualNetworkSubnets.value[0].privateEndpointNetworkPolicies 'Private endpoint policy conversion is incorrect.'
  Assert-Equal $false $result.parameters.virtualNetworkSubnets.value[0].defaultOutboundAccess 'Default outbound access conversion is incorrect.'
  Assert-Equal 'nsg-workload' $result.parameters.virtualNetworkSubnets.value[0].networkSecurityGroup.name 'NSG conversion is incorrect.'
  Assert-Equal 'allowHttps' $result.parameters.virtualNetworkSubnets.value[0].networkSecurityGroup.securityRules[0].name 'NSG rule name conversion is incorrect.'
  Assert-Equal 'destinationPortRange' @($result.parameters.virtualNetworkSubnets.value[0].networkSecurityGroup.securityRules[0].properties.Keys | Where-Object { $_ -eq 'destinationPortRange' })[0] 'NSG rule property conversion is incorrect.'
  Assert-Equal 'PRJ-1234' $result.parameters.subscriptionTags.value.projectcode 'Cost allocation tag is missing.'
  Assert-Equal 500 $result.parameters.budgetAmount.value 'Budget amount is incorrect.'
  Assert-Equal 2 $result.parameters.budgetContactEmails.value.Count 'Budget contacts are incorrect.'
  Assert-Equal 80 $result.parameters.budgetActualThresholds.value[0] 'Actual budget threshold is incorrect.'
  Assert-Equal 100 $result.parameters.budgetForecastThresholds.value[0] 'Forecast budget threshold is incorrect.'
  Assert-Equal 'Reader' $result.parameters.roleAssignments.value[0].definition 'Role assignment conversion is incorrect.'
  Assert-Equal '/resourceGroups/rg-workload' $result.parameters.roleAssignments.value[0].relativeScope 'Role assignment scope conversion is incorrect.'
  Assert-Equal 'Group' $result.parameters.roleAssignments.value[0].principalType 'Role assignment principal type conversion is incorrect.'
  Assert-Equal 'Workload readers' $result.parameters.roleAssignments.value[0].description 'Role assignment description conversion is incorrect.'
  Assert-Equal 'constrainRoles' $result.parameters.roleAssignments.value[0].roleAssignmentCondition.roleConditionType.templateName 'Role assignment condition conversion is incorrect.'
  Assert-Equal 'id-workload' $result.parameters.userAssignedManagedIdentities.value[0].name 'Managed identity conversion is incorrect.'
  Assert-Equal $false $result.parameters.enableTelemetry.value 'Telemetry setting is incorrect.'
  Assert-Equal 0 $result.parameters.resourceProviders.value.Count 'Explicit resource provider configuration was not preserved.'

  $ownerOnlyBudgetRequest = $request.Clone()
  $ownerOnlyBudgetRequest.budget = @{
    amount = 500
    contacts = @()
  }
  $ownerOnlyBudgetResult = ConvertTo-BicepSubscriptionParameters -Request $ownerOnlyBudgetRequest -Platform $platform -RequestName 'owner-only-budget'
  Assert-Equal 'System.Object[]' $ownerOnlyBudgetResult.parameters.budgetContactEmails.value.GetType().FullName 'A single budget contact must remain an array.'
  Assert-Equal 1 $ownerOnlyBudgetResult.parameters.budgetContactEmails.value.Count 'The owner-only budget contact array is incorrect.'
  Assert-Equal 'owner@example.com' $ownerOnlyBudgetResult.parameters.budgetContactEmails.value[0] 'The owner-only budget contact is incorrect.'

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

  $unsupportedSubnetRequest = $request.Clone()
  $unsupportedSubnetRequest.network = @{
    enabled = $true
    addressSpace = @('10.30.0.0/16')
    subnets = @{
      workload = @{
        address_prefixes = @('10.30.1.0/24')
        unsupported_property = $true
      }
    }
  }
  Assert-Throws `
    -Script { ConvertTo-BicepSubscriptionParameters -Request $unsupportedSubnetRequest -Platform $platform -RequestName 'unsupported-subnet' } `
    -MessagePattern "*Subnet 'workload' contains properties that the Bicep starter does not support: unsupported_property.*"

  $multiplePrefixRequest = $request.Clone()
  $multiplePrefixRequest.network = @{
    enabled = $true
    addressSpace = @('10.40.0.0/16')
    subnets = @{
      workload = @{
        address_prefixes = @('10.40.1.0/25', '10.40.1.128/25')
      }
    }
  }
  Assert-Throws `
    -Script { ConvertTo-BicepSubscriptionParameters -Request $multiplePrefixRequest -Platform $platform -RequestName 'multiple-prefixes' } `
    -MessagePattern "*must declare exactly one address prefix for Bicep AVM 0.8.0*"

  $invalidRoleAssignmentRequest = $request.Clone()
  $invalidRoleAssignmentRequest.roleAssignments = @{
    reader = @{
      principal_id = ''
      role_definition_id_or_name = 'Reader'
    }
  }
  Assert-Throws `
    -Script { ConvertTo-BicepSubscriptionParameters -Request $invalidRoleAssignmentRequest -Platform $platform -RequestName 'invalid-role-assignment' } `
    -MessagePattern "*missing required field: principal_id*"

  Write-Host 'Bicep starter tests passed.' -ForegroundColor Green
}
finally {
  Remove-Module SubscriptionVending.Bicep -ErrorAction SilentlyContinue
}
