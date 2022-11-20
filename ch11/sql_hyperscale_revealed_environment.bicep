@description('The primary region for the SQL Hyperscale Revealed demo environment')
param primaryRegion string = 'West US 3'

@description('The failover region for the SQL Hyperscale Revealed demo environment')
param failoverRegion string = 'East US'

@description('The string that will be suffixed into resource names to ensure they are unique')
param resourceNameSuffix string

@description('The envrionment tag that will be used to tag all resources created by this template')
param environment string = 'SQL Hyperscale Revealed demo'

@description('The id of the SQL Administrators Azure AD Group')
param sqlAdministratorsGroupId string


// Deploy to the subscription scope so we can create resource groups
targetScope = 'subscription'

// Variables to help with resource naming
var baseResourcePrefix = 'shr'
var primaryRegionPrefix = '${baseResourcePrefix}01'
var failoverRegionPrefix = '${baseResourcePrefix}02'
var primaryRegionResourceGroupName = '${primaryRegionPrefix}-${resourceNameSuffix}-rg'
var failoverRegionResourceGroupName = '${failoverRegionPrefix}-${resourceNameSuffix}-rg'
var privateZone = 'privatelink.${az.environment().suffixes.sqlServerHostname}'

// Resource Groups
resource primaryResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: primaryRegionResourceGroupName
  location: primaryRegion
  tags: {
    Environment: environment
  }
}

resource failoverResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: failoverRegionResourceGroupName
  location: failoverRegion
  tags: {
    Environment: environment
  }
}

// Virtual networks
var primaryVirtualNetworkName = 'sqlhr01-${resourceNameSuffix}-vnet'

module primaryVirtualNetwork './modules/virtual_network_with_mgmt.bicep' = {
  name: 'primaryVirtualNetwork'
  scope: primaryResourceGroup
  params: {
    name: primaryVirtualNetworkName
    location: primaryRegion
    environment: environment
    addressSpace: '10.0.0.0/16'
    appSubnetAddressSpace: '10.0.1.0/24'
    dataSubnetAddressSpace: '10.0.2.0/24'
    managementSubnetAddressSpace: '10.0.3.0/24'
    azureBastionSubnetAddressSpace: '10.0.4.0/24'
  }
}

var failoverVirtualNetworkName = 'sqlhr02-${resourceNameSuffix}-vnet'

module failoverVirtualNetwork './modules/virtual_network_with_mgmt.bicep' = {
  name: 'failoverVirtualNetwork'
  scope: failoverResourceGroup
  params: {
    name: failoverVirtualNetworkName
    location: failoverRegion
    environment: environment
    addressSpace: '10.1.0.0/16'
    appSubnetAddressSpace: '10.1.1.0/24'
    dataSubnetAddressSpace: '10.1.2.0/24'
    managementSubnetAddressSpace: '10.1.3.0/24'
    azureBastionSubnetAddressSpace: '10.1.4.0/24'
  }
}

// User Assigned Managed Identity for Logical Servers to access Key Vault
var userAssignedManagedIdentityName = '${baseResourcePrefix}-${resourceNameSuffix}-umi'

module userAssignedManagedIdentity './modules/user_assigned_managed_identity.bicep' = {
  name: 'userAssignedManagedIdentity'
  scope: primaryResourceGroup
  params: {
    name: userAssignedManagedIdentityName
    location: primaryRegion
    environment: environment
  }
}

// Key Vault with TDE Protector Key and grant Key Vault Crypto Service Encryption Role
// to the User Assigned Managed Identity for the TDE Protector Key
var keyVaultName = 'sqlhr-${resourceNameSuffix}-kv'

module keyVault './modules/key_vault_with_tde_protector.bicep' = {
  name: 'keyVault'
  scope: primaryResourceGroup
  params: {
    name: keyVaultName
    location: primaryRegion
    environment: environment
    tenantId: subscription().tenantId
    keyName: '${baseResourcePrefix}-${resourceNameSuffix}-tdeprotector'
    userAssignedManagedIdentityPrincipalId: userAssignedManagedIdentity.outputs.userAssignedManagedIdentityPrincipalId
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

// Primary Azure SQL Logical Server
module primaryLogicalServer './modules/sql_logical_server.bicep' = {
  name: 'primaryLogicalServer'
  scope: primaryResourceGroup
  params: {
    name: '${primaryRegionPrefix}-${resourceNameSuffix}'
    location: primaryRegion
    environment: environment
    tenantId: subscription().tenantId
    userAssignedManagedIdentityResourceId: userAssignedManagedIdentity.outputs.userAssignedManagedIdentityResourceId
    tdeProtectorKeyId: keyVault.outputs.tdeProtectorKeyId
    sqlAdministratorsGroupId: sqlAdministratorsGroupId
  }
}

// Primary Azure SQL Hyperscale Database
module primaryLogicalDatabase './modules/sql_hyperscale_database.bicep' = {
  name: 'primaryDatabase'
  scope: primaryResourceGroup
  params: {
    name: 'hyperscaledb'
    location: primaryRegion
    environment: environment
    logicalServerName: '${primaryRegionPrefix}-${resourceNameSuffix}'
  }
}
