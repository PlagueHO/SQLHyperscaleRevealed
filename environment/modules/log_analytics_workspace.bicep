param name string
param location string
param environment string = 'SQL Hyperscale Revealed demo'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: name
  location: location
  properties: {
    workspaceCapping: {
      dailyQuotaGb: 10 // Make sure we don't spend too much for demo
    }
  }
  tags: {
    Environment: environment
  }
}
