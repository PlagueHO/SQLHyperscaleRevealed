param name string
param location string
param environment string = 'SQL Hyperscale Reveaeled demo'

targetScope = 'subscription'

resource resource_group 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: name
  location: location
  tags: {
    Environment: environment
  }
}
