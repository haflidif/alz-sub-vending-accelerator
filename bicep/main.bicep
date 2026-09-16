metadata name = 'Subscription vending accelerator'
metadata description = 'Deploys one governed landing zone subscription through the Azure Verified Modules Bicep sub-vending pattern.'

targetScope = 'managementGroup'

@minLength(1)
@maxLength(63)
param subscriptionAliasName string

@maxLength(36)
param existingSubscriptionId string = ''

@minLength(1)
@maxLength(63)
param subscriptionDisplayName string

@minLength(1)
param subscriptionBillingScope string

@allowed([
  'Production'
  'DevTest'
])
param subscriptionWorkload string = 'Production'

@minLength(1)
param subscriptionManagementGroupId string

param subscriptionTags object = {}

param virtualNetworkEnabled bool = false
param virtualNetworkResourceGroupName string = ''
param virtualNetworkLocation string = deployment().location
param virtualNetworkName string = ''
param virtualNetworkAddressSpace string[] = []
param virtualNetworkSubnets array = []
param virtualNetworkPeeringEnabled bool = false
param hubNetworkResourceId string = ''

param roleAssignments array = []

param userAssignedIdentityResourceGroupName string = ''
param userAssignedManagedIdentities array = []

param budgetEnabled bool = false
param budgetName string = ''
param budgetAmount int = 100
param budgetContactEmails array = []
param budgetActualThresholds int[] = [80]
param budgetForecastThresholds int[] = [100]

param resourceProviders object?

param enableTelemetry bool = true

var defaultResourceProviders = loadJsonContent('./default-resource-providers.json')

module subscriptionVending 'br/public:avm/ptn/lz/sub-vending:0.8.0' = {
  name: take('sub-vending-${subscriptionAliasName}-${uniqueString(subscriptionAliasName, deployment().name)}', 64)
  params: {
    subscriptionAliasEnabled: empty(existingSubscriptionId)
    existingSubscriptionId: existingSubscriptionId
    subscriptionAliasName: subscriptionAliasName
    subscriptionDisplayName: subscriptionDisplayName
    subscriptionBillingScope: subscriptionBillingScope
    subscriptionWorkload: subscriptionWorkload
    subscriptionManagementGroupAssociationEnabled: true
    subscriptionManagementGroupId: subscriptionManagementGroupId
    subscriptionTags: subscriptionTags
    virtualNetworkEnabled: virtualNetworkEnabled
    virtualNetworkResourceGroupName: virtualNetworkResourceGroupName
    virtualNetworkResourceGroupLockEnabled: false
    virtualNetworkLocation: virtualNetworkLocation
    virtualNetworkName: virtualNetworkEnabled ? virtualNetworkName : null
    virtualNetworkAddressSpace: virtualNetworkAddressSpace
    virtualNetworkSubnets: virtualNetworkSubnets
    virtualNetworkPeeringEnabled: virtualNetworkPeeringEnabled
    hubNetworkResourceId: hubNetworkResourceId
    roleAssignmentEnabled: !empty(roleAssignments)
    roleAssignments: roleAssignments
    userAssignedIdentityResourceGroupName: userAssignedIdentityResourceGroupName
    userAssignedManagedIdentities: userAssignedManagedIdentities
    userAssignedIdentitiesResourceGroupLockEnabled: false
    budgetName: ''
    resourceProviders: resourceProviders ?? defaultResourceProviders
    enableTelemetry: enableTelemetry
  }
}

module subscriptionBudget './modules/budgetWrapper.bicep' = if (budgetEnabled) {
  name: take('budget-${subscriptionAliasName}-${uniqueString(subscriptionAliasName, deployment().name)}', 64)
  params: {
    subscriptionId: subscriptionVending.outputs.subscriptionId
    name: budgetName
    amount: budgetAmount
    contactEmails: budgetContactEmails
    actualThresholds: budgetActualThresholds
    forecastThresholds: budgetForecastThresholds
  }
}

output subscriptionId string = subscriptionVending.outputs.subscriptionId
output subscriptionResourceId string = subscriptionVending.outputs.subscriptionResourceId
output failedResourceProviders string = subscriptionVending.outputs.failedResourceProviders
output failedResourceProviderFeatures string = subscriptionVending.outputs.failedResourceProvidersFeatures
output budgetResourceId string = subscriptionBudget.?outputs.resourceId ?? ''
