targetScope = 'managementGroup'

param subscriptionId string
param name string
param amount int
param contactEmails string[]
param actualThresholds int[]
param forecastThresholds int[]

module budget './budget.bicep' = {
  scope: subscription(subscriptionId)
  name: take('budget-${name}-${uniqueString(subscriptionId, name, deployment().name)}', 64)
  params: {
    name: name
    amount: amount
    contactEmails: contactEmails
    actualThresholds: actualThresholds
    forecastThresholds: forecastThresholds
  }
}

output resourceId string = budget.outputs.resourceId
