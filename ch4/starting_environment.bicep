@description('The primary region for the SQL Hyperscale Revealed demo environment')
param primaryRegion string = 'West US 3'

@description('The failover region for the SQL Hyperscale Revealed demo environment')
param failoverRegion string = 'East US'

@description('The string that will be suffixed into resource names to ensure they are unique')
param resourceNameSuffix string

@description('The envrionment tag that will be used to tag all resources created by this template')
param environment string = 'SQL Hyperscale Revealed demo'

// Deploy to the subscription scope so we can create resource groups
targetScope = 'subscription'

// Create the resource groups
var primaryResourceGroupName = 'sqlhr01-${resourceNameSuffix}-rg'

resource primaryResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: primaryResourceGroupName
  location: primaryRegion
  tags: {
    Environment: environment
  }
}

var failoverResourceGroupName = 'sqlhr02-${resourceNameSuffix}-rg'

resource failoverResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: failoverResourceGroupName
  location: failoverRegion
  tags: {
    Environment: environment
  }
}

// Create the virtual networks
var primaryVirtualNetworkName = 'sqlhr01-${resourceNameSuffix}-vnet'

module primaryVirtualNetwork './modules/virtual_network.bicep' = {
  name: 'primaryVirtualNetwork'
  scope: primaryResourceGroup
  params: {
    name: primaryVirtualNetworkName
    location: primaryRegion
    environment: environment
    addressSpace: '10.0.0.0/16'
    appSubnetAddressSpace: '10.0.1.0/24'
    dataSubnetAddressSpace: '10.0.2.0/24'
  }
}

var failoverVirtualNetworkName = 'sqlhr02-${resourceNameSuffix}-vnet'

module failoverVirtualNetwork './modules/virtual_network.bicep' = {
  name: 'failoverVirtualNetwork'
  scope: failoverResourceGroup
  params: {
    name: failoverVirtualNetworkName
    location: failoverRegion
    environment: environment
    addressSpace: '10.1.0.0/16'
    appSubnetAddressSpace: '10.1.1.0/24'
    dataSubnetAddressSpace: '10.1.2.0/24'
  }
}

// Create Key Vault
var keyVaultName = 'sqlhr-${resourceNameSuffix}-kv'

module keyVault './modules/key_vault.bicep' = {
  name: 'keyVault'
  scope: primaryResourceGroup
  params: {
    name: keyVaultName
    location: primaryRegion
    environment: environment
    tenantId: subscription().tenantId
  }
}

// Create Log Analytics workspaces
var primaryLogAnalyticsWorkspaceName = 'sqlhr01-${resourceNameSuffix}-law'

module primaryLogAnalyticsWorkspace './modules/log_analytics_workspace.bicep' = {
  name: 'primaryLogAnalyticsWorkspace'
  scope: primaryResourceGroup
  params: {
    name: primaryLogAnalyticsWorkspaceName
    location: primaryRegion
    environment: environment
  }
}

var failoverLogAnalyticsWorkspaceName = 'sqlhr02-${resourceNameSuffix}-law'

module failoverLogAnalyticsWorkspace './modules/log_analytics_workspace.bicep' = {
  name: 'failoverLogAnalyticsWorkspace'
  scope: failoverResourceGroup
  params: {
    name: failoverLogAnalyticsWorkspaceName
    location: failoverRegion
    environment: environment
  }
}

output primaryResourceGroupName string = primaryResourceGroupName
output failoverResourceGroupName string = failoverResourceGroupName
output primaryVirtualNetworkName string = primaryVirtualNetworkName
output failoverVirtualNetworkName string = failoverVirtualNetworkName
output keyVaultName string = keyVaultName
output primaryLogAnalyticsWorkspaceName string = primaryLogAnalyticsWorkspaceName
output failoverLogAnalyticsWorkspaceName string = failoverLogAnalyticsWorkspaceName
