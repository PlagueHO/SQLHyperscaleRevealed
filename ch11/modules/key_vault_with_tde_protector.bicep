param name string
param location string
param tenantId string
param environment string = 'SQL Hyperscale Revealed demo'
param keyName string
param managedIdentityId string

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

resource tdeProtectorKey 'Microsoft.KeyVault/vaults/keys@2022-07-01' = {
  name: '${keyVault.name}/${keyName}'
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'wrapKey'
      'unwrapKey'
    ]
  }
}

resource keyVaultCryptoServiceEncryptionRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'e147488a-f6f5-4113-8e2d-b22465e65bf6' // Key Vault Crypto Service Encryption Role
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, managedIdentityId, keyVaultCryptoServiceEncryptionRoleDefinition.id)
  properties: {
    roleDefinitionId: keyVaultCryptoServiceEncryptionRoleDefinition.id
    principalId: managedIdentityId
    principalType: 'ServicePrincipal'
  }
}

output keyVault object = keyVault
output tdeProtectorKey object = tdeProtectorKey
