param name string
param location string
param tenantId string
param environment string = 'SQL Hyperscale Revealed demo'

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    enableSoftDelete: true
    enablePurgeProtection: true
    enableRbacAuthorization: true
    tenantId: tenantId
  }
  tags: {
    Environment: environment
  }
}
