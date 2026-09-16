targetScope = 'subscription'

@minLength(1)
param name string

@minValue(1)
param amount int

param startDate string = '${utcNow('yyyy')}-${utcNow('MM')}-01T00:00:00Z'
param endDate string = '2099-12-31T23:59:59Z'
param contactEmails string[]
param actualThresholds int[] = []
param forecastThresholds int[] = []

var actualNotifications = toObject(
  actualThresholds,
  threshold => 'actual${threshold}',
  threshold => {
    enabled: true
    operator: 'GreaterThan'
    threshold: threshold
    thresholdType: 'Actual'
    contactEmails: contactEmails
    contactGroups: []
    contactRoles: []
  }
)

var forecastNotifications = toObject(
  forecastThresholds,
  threshold => 'forecast${threshold}',
  threshold => {
    enabled: true
    operator: 'GreaterThan'
    threshold: threshold
    thresholdType: 'Forecasted'
    contactEmails: contactEmails
    contactGroups: []
    contactRoles: []
  }
)

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: name
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
      endDate: endDate
    }
    notifications: union(actualNotifications, forecastNotifications)
  }
}

output resourceId string = budget.id
