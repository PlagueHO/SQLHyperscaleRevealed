param name string
param location string
param tenantId string
param environment string = 'SQL Hyperscale Revealed demo'
param sqlAdministratorsGroupId string
param tdeProtectorKeyId string
param userAssignedManagedIdentityResourceId string
param logAnalyticsWorkspaceName string
param logAnalyticsWorkspaceId string

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
    keyId: tdeProtectorKeyId
    primaryUserAssignedIdentityId: userAssignedManagedIdentityResourceId
    publicNetworkAccess: 'Disabled'
  }
  tags: {
    Environment: environment
  }
}

resource sqlLogicalServerAuditing 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'Send all audit to ${logAnalyticsWorkspaceName}'
  scope: sqlLogicalServer
  properties: {
    logAnalyticsDestinationType: 'string'
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
    workspaceId: logAnalyticsWorkspaceId
  }
}

resource sqlLogicalServerAuditingSettings 'Microsoft.Sql/servers/auditingSettings@2022-05-01-preview' = {
  name: '${sqlLogicalServer.name}/Default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
  }
}
