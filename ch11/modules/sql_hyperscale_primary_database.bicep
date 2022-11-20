param name string
param location string
param environment string = 'SQL Hyperscale Revealed demo'
param logicalServerName string
param logAnalyticsWorkspaceName string
param logAnalyticsWorkspaceId string

resource sqlLogicalServer 'Microsoft.Sql/servers@2022-05-01-preview' existing = {
  name: logicalServerName
}

resource sqlHyperscaleDatabase 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  name: name
  location: location
  parent: sqlLogicalServer
  sku: {
    name: 'HS_Gen5'
    capacity: 2
    family: 'Gen5'
  }
  properties: {
    highAvailabilityReplicaCount: 2
    requestedBackupStorageRedundancy: 'GeoZone'
    zoneRedundant: true
  }
  tags: {
    Environment: environment
  }
}

resource sqlHyperscaleDatabaseDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'Send all logs to ${logAnalyticsWorkspaceName}'
  scope: sqlHyperscaleDatabase
  properties: {
    logAnalyticsDestinationType: 'string'
    logs: [
      {
        category: 'SQLInsights'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'AutomaticTuning'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'QueryStoreRuntimeStatistics'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'Errors'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'DatabaseWaitStatistics'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'Timeouts'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'Blocks'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
      {
        category: 'Deadlocks'
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
