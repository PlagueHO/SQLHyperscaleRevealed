param name string
param location string
param tenantId string
param environment string = 'SQL Hyperscale Reveaeled demo'

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: tenantId
    enableSoftDelete: true
    enablePurgeProtection: true
  }
  tags: {
    Environment: environment
  }
}
