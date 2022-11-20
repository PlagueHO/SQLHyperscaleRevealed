param name string
param location string
param environment string = 'SQL Hyperscale Revealed demo'
param logicalServerName string

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
