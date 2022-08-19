@description('The primary region for the SQL Hyperscale Revealed demo environment')
param primaryRegion string = 'West US 3'

@description('The failover region for the SQL Hyperscale Revealed demo environment')
param failoverRegion string = 'East US'

@description('The string that will be suffixed into resource names to ensure they are unique')
param resourceNameSuffix string

@description('The envrionment tag that will be used to tag all resources created by this template')
param environment string = 'SQL Hyperscale Revealed demo'

// Create the resource groups
var primaryResourceGroupName = 'sqlhr01-${resourceNameSuffix}-rg'


