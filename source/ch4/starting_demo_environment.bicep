
@description('The primary region for the SQL Hyperscale Revealed demo environment')
param primaryRegion string = 'West US 3'

@description('The failover region for the SQL Hyperscale Revealed demo environment')
param failoverRegion string = 'East US'

@description('The string that will be suffixed into resource names to ensure they are unique')
param resourceNameSuffix string

@description('The envrionment tag that will be used to tag all resources created by this template')
param environment string = 'SQL Hyperscale Reveaeled demo'

// Create the resource groups
var primaryResourceGroupName = 'sqlhr01-${resourceNameSuffix}-rg'

module primary_resource_group './modules/resource_group.bicep' = {
  name: 'primary_resource_group'
  scope: subscription()
  params: {
    name: primaryResourceGroupName
    location: primaryRegion
    environment: environment
  }
}

var failoverResourceGroupName = 'sqlhr01-${resourceNameSuffix}-rg'

module failover_resource_group './modules/resource_group.bicep' = {
  name: 'failover_resource_group'
  scope: subscription()
  params: {
    name: failoverResourceGroupName
    location: failoverRegion
    environment: environment
  }
}

// Create the virtual networks
var primaryVirtualNetworkName = 'sqlhr01-${resourceNameSuffix}-vnet'

module primary_virtual_network './modules/virtual_network.bicep' = {
  name: 'primary_virtual_network'
  scope: resourceGroup(primary_resource_group.name)
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

module failover_virtual_network './modules/virtual_network.bicep' = {
  name: 'failover_virtual_network'
  scope: resourceGroup(failover_resource_group.name)
  params: {
    name: failoverVirtualNetworkName
    location: failoverRegion
    environment: environment
    addressSpace: '10.1.0.0/16'
    appSubnetAddressSpace: '10.1.1.0/24'
    dataSubnetAddressSpace: '10.1.2.0/24'
  }
}
