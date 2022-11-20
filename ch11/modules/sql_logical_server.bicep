param name string
param location string
param tenantId string
param environment string = 'SQL Hyperscale Revealed demo'
param sqlAdministratorsGroupId string
param tdeProtectorKeyId string
param userAssignedManagedIdentityResourceId string
param vnetId string
param dataSubnetId string
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

resource sqlLogicalServerPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: '${name}-pe'
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${name}-pe'
        properties: {
          groupIds: [
            'sqlServer'
          ]
          privateLinkServiceId: sqlLogicalServer.id
        }
      }
    ]
    subnet: {
      id: dataSubnetId
    }
  }
  tags: {
    Environment: environment
  }
}

var privateZoneName = 'privatelink.${az.environment().suffixes.sqlServerHostname}'

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateZoneName
  location: 'global'
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name:  '${name}-dnslink'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource pvtEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  name: '${name}-zonegroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: '${name}-config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    sqlLogicalServerPrivateEndpoint
  ]
}

resource masterDatabase 'Microsoft.Sql/servers/databases@2022-05-01-preview' existing = {
  name: 'master'
  parent: sqlLogicalServer
}

resource sqlLogicalServerAuditing 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'Send all audit to ${logAnalyticsWorkspaceName}'
  scope: masterDatabase
  properties: {
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
  name: '${sqlLogicalServer.name}/default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
  }
}
