param name string
param location string
param tenantId string
param environment string = 'SQL Hyperscale Revealed demo'
param sqlAdministratorsGroupId string
param tdeProtectorKey object
param userAssignedManagedIdentityResourceId string

resource sqlLogicalServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: name
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedManagedIdentityResourceId}': {}
    }
  }
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: 'SQL Administrators'
      principalType: 'Group'
      sid: sqlAdministratorsGroupId
      tenantId: tenantId
    }
    keyId: tdeProtectorKey.id
    primaryUserAssignedIdentityId: userAssignedManagedIdentityResourceId
    publicNetworkAccess: 'Disabled'
  }
  tags: {
    Environment: environment
  }
}
