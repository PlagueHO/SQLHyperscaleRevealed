param name string
param location string
param environment string = 'SQL Hyperscale Revealed demo'

resource userAssignedManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: name
  location: location
  tags: {
    Environment: environment
  }
}

output userAssignedManagedIdentityResourceId string = userAssignedManagedIdentity.id
output userAssignedManagedIdentityPrincipalId string = userAssignedManagedIdentity.properties.principalId
