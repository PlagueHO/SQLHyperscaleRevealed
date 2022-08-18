param administratorLogin string = ''

@secure()
param administratorLoginPassword string = ''
param administrators object = {
}
param collation string
param databaseName string
param tier string
param skuName string
param location string
param maxSizeBytes int
param serverName string
param sampleName string = ''
param zoneRedundant bool = false
param licenseType string = ''
param readScaleOut string = 'Disabled'
param numberOfReplicas int = 0
param minCapacity string = ''
param autoPauseDelay string = ''
param enableADS bool = false
param allowAzureIps bool = true
param databaseTags object = {
}
param serverTags object = {
}
param enableVA bool = false

@description('To enable vulnerability assessments, the user deploying this template must have an administrator or owner permissions.')
param useVAManagedIdentity bool = false
param enablePrivateEndpoint bool = false
param privateEndpointNestedTemplateId string = ''
param privateEndpointSubscriptionId string = ''
param privateEndpointResourceGroup string = ''
param privateEndpointName string = ''
param privateEndpointLocation string = ''
param privateEndpointSubnetId string = ''
param privateLinkServiceName string = ''
param privateLinkServiceServiceId string = ''
param privateEndpointVnetSubscriptionId string = ''
param privateEndpointVnetResourceGroup string = ''
param privateEndpointVnetName string = ''
param privateEndpointSubnetName string = ''
param enablePrivateDnsZone bool = false
param privateLinkPrivateDnsZoneFQDN string = ''
param privateEndpointDnsRecordUniqueId string = ''
param privateEndpointTemplateLink string = ''
param privateDnsForPrivateEndpointTemplateLink string = ''
param privateDnsForPrivateEndpointNicTemplateLink string = ''
param privateDnsForPrivateEndpointIpConfigTemplateLink string = ''
param allowClientIp bool = false
param clientIpRuleName string = ''
param clientIpValue string = ''
param publicNetworkAccess string = ''
param requestedBackupStorageRedundancy string = ''
param maintenanceConfigurationId string = ''

@description('Uri of the encryption key.')
param keyId string = ''

@description('Azure Active Directory identity of the server.')
param identity object = {
}

@description('resource id of a user assigned identity to be used by default.')
param primaryUserAssignedIdentityId string = ''
param minimalTlsVersion string = ''
param enableSqlLedger bool = false
param connectionType string = ''
param enableDigestStorage string = ''
param digestStorageOption string = ''
param digestStorageName string = ''
param blobStorageContainerName string = ''
param retentionDays string = ''
param retentionPolicy bool = true
param digestAccountResourceGroup string = ''
param digestRegion string = ''
param storageAccountdigestRegion string = ''
param isNewDigestLocation bool = false
param isPermissionAssigned bool = false
param sqlLedgerTemplateLink string = ''
param servicePrincipal object = {
}

var subscriptionId = subscription().subscriptionId
var resourceGroupName = resourceGroup().name
var uniqueStorage = uniqueString(subscriptionId, resourceGroupName, location)
var storageName_var = toLower('sqlva${uniqueStorage}')
var privateEndpointContainerTemplateName = 'PrivateEndpointContainer-${(enablePrivateEndpoint ? privateEndpointNestedTemplateId : '')}'
var subnetPoliciesTemplateName_var = 'SubnetPolicies-${(enablePrivateEndpoint ? privateEndpointNestedTemplateId : '')}'
var privateEndpointTemplateName_var = 'PrivateEndpoint-${(enablePrivateEndpoint ? privateEndpointNestedTemplateId : '')}'
var deploymentTemplateApi = '2018-05-01'
var privateEndpointApi = '2019-04-01'
var privateEndpointId = (enablePrivateEndpoint ? resourceId(privateEndpointSubscriptionId, privateEndpointResourceGroup, 'Microsoft.Network/privateEndpoints', privateEndpointName) : '')
var privateEndpointVnetId = (enablePrivateEndpoint ? resourceId(privateEndpointVnetSubscriptionId, privateEndpointVnetResourceGroup, 'Microsoft.Network/virtualNetworks', privateEndpointVnetName) : '')
var privateEndpointSubnetResourceId = (enablePrivateEndpoint ? resourceId(privateEndpointVnetSubscriptionId, privateEndpointVnetResourceGroup, 'Microsoft.Network/virtualNetworks/subnets', privateEndpointVnetName, privateEndpointSubnetName) : '')
var uniqueRoleGuid = guid(storageName.id, StorageBlobContributor, serverName_resource.id)
var StorageBlobContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

resource storageName 'Microsoft.Storage/storageAccounts@2019-04-01' = if (enableVA) {
  name: storageName_var
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: 'true'
    allowBlobPublicAccess: 'false'
  }
}

resource storageName_Microsoft_Authorization_uniqueRoleGuid 'Microsoft.Storage/storageAccounts/providers/roleAssignments@2018-09-01-preview' = if (enableVA) {
  name: '${storageName_var}/Microsoft.Authorization/${uniqueRoleGuid}'
  properties: {
    roleDefinitionId: StorageBlobContributor
    principalId: reference(serverName_resource.id, '2018-06-01-preview', 'Full').identity.principalId
    scope: storageName.id
    principalType: 'ServicePrincipal'
  }
}

resource serverName_resource 'Microsoft.Sql/servers@2021-05-01-preview' = {
  location: location
  tags: serverTags
  name: serverName
  properties: {
    version: '12.0'
    minimalTlsVersion: minimalTlsVersion
    publicNetworkAccess: publicNetworkAccess
    administrators: administrators
    primaryUserAssignedIdentityId: primaryUserAssignedIdentityId
    servicePrincipal: servicePrincipal
  }
  identity: identity
}

resource serverName_databaseName 'Microsoft.Sql/servers/databases@2021-02-01-preview' = {
  parent: serverName_resource
  location: location
  tags: databaseTags
  name: '${databaseName}'
  properties: {
    collation: collation
    maxSizeBytes: maxSizeBytes
    sampleName: sampleName
    zoneRedundant: zoneRedundant
    licenseType: licenseType
    readScale: readScaleOut
    highAvailabilityReplicaCount: numberOfReplicas
    minCapacity: minCapacity
    autoPauseDelay: autoPauseDelay
    requestedBackupStorageRedundancy: requestedBackupStorageRedundancy
    isLedgerOn: enableSqlLedger
    maintenanceConfigurationId: maintenanceConfigurationId
  }
  sku: {
    name: skuName
    tier: tier
  }
}

resource serverName_AllowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallrules@2014-04-01-preview' = if (allowAzureIps) {
  parent: serverName_resource
  location: location
  name: 'AllowAllWindowsAzureIps'
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

resource serverName_Default 'Microsoft.Sql/servers/connectionPolicies@2014-04-01' = {
  parent: serverName_resource
  location: location
  name: 'Default'
  properties: {
    connectionType: connectionType
  }
}

resource serverName_clientIpRuleName 'Microsoft.Sql/servers/firewallrules@2014-04-01-preview' = if (allowClientIp) {
  parent: serverName_resource
  location: location
  name: '${clientIpRuleName}'
  properties: {
    endIpAddress: clientIpValue
    startIpAddress: clientIpValue
  }
}

resource Microsoft_Sql_servers_securityAlertPolicies_serverName_Default 'Microsoft.Sql/servers/securityAlertPolicies@2017-03-01-preview' = if (enableADS) {
  parent: serverName_resource
  name: 'Default'
  properties: {
    state: 'Enabled'
    disabledAlerts: []
    emailAddresses: []
    emailAccountAdmins: true
  }
  dependsOn: [

    serverName_databaseName
  ]
}

resource Microsoft_Sql_servers_vulnerabilityAssessments_serverName_Default 'Microsoft.Sql/servers/vulnerabilityAssessments@2018-06-01-preview' = if (enableVA) {
  parent: serverName_resource
  name: 'Default'
  properties: {
    storageContainerPath: (enableVA ? '${storageName.properties.primaryEndpoints.blob}vulnerability-assessment' : '')
    storageAccountAccessKey: ((enableVA && (!useVAManagedIdentity)) ? listKeys(storageName_var, '2018-02-01').keys[0].value : '')
    recurringScans: {
      isEnabled: true
      emailSubscriptionAdmins: true
      emails: []
    }
  }
  dependsOn: [

    Microsoft_Sql_servers_securityAlertPolicies_serverName_Default
  ]
}

module subnetPoliciesTemplateName './modules/subnetPoliciesTemplateName.bicep' = if (enablePrivateEndpoint) {
  name: subnetPoliciesTemplateName_var
  scope: resourceGroup((enablePrivateEndpoint ? privateEndpointVnetSubscriptionId : subscriptionId), (enablePrivateEndpoint ? privateEndpointVnetResourceGroup : resourceGroupName))
  params: {
    variables_privateEndpointApi: privateEndpointApi
    privateEndpointVnetName: privateEndpointVnetName
    privateEndpointSubnetName: privateEndpointSubnetName
    privateEndpointLocation: privateEndpointLocation
  }
}

module privateEndpointTemplateName '?' /*TODO: replace with correct path to [parameters('privateEndpointTemplateLink')]*/ = if (enablePrivateEndpoint) {
  name: privateEndpointTemplateName_var
  scope: resourceGroup((enablePrivateEndpoint ? privateEndpointSubscriptionId : subscriptionId), (enablePrivateEndpoint ? privateEndpointResourceGroup : resourceGroupName))
  params: {
    privateEndpointName: privateEndpointName
    privateEndpointConnectionId: ''
    privateEndpointConnectionName: privateLinkServiceName
    privateEndpointId: privateEndpointId
    privateEndpointApiVersion: privateEndpointApi
    privateLinkServiceId: privateLinkServiceServiceId
    groupId: 'SqlServer'
    subnetId: privateEndpointSubnetResourceId
    location: privateEndpointLocation
    tags: {
    }
  }
  dependsOn: [
    resourceId(subscriptionId, resourceGroupName, 'Microsoft.Sql/servers/databases/', serverName, databaseName)
    subnetPoliciesTemplateName
  ]
}

module PrivateDns_privateEndpointNestedTemplateId './modules/PrivateDns_privateEndpointNestedTemplateId.bicep' = if (enablePrivateEndpoint && enablePrivateDnsZone) {
  name: 'PrivateDns-${privateEndpointNestedTemplateId}'
  scope: resourceGroup((enablePrivateEndpoint ? privateEndpointVnetSubscriptionId : subscriptionId), (enablePrivateEndpoint ? privateEndpointVnetResourceGroup : resourceGroupName))
  params: {
    reference_concat_Microsoft_Resources_deployments_variables_privateEndpointTemplateName_outputs_networkInterfaceId_value: privateEndpointTemplateName.properties
    variables_privateEndpointVnetId: privateEndpointVnetId
    variables_deploymentTemplateApi: deploymentTemplateApi
    privateLinkPrivateDnsZoneFQDN: privateLinkPrivateDnsZoneFQDN
    privateEndpointDnsRecordUniqueId: privateEndpointDnsRecordUniqueId
    privateDnsForPrivateEndpointTemplateLink: privateDnsForPrivateEndpointTemplateLink
    enablePrivateEndpoint: enablePrivateEndpoint
    privateDnsForPrivateEndpointNicTemplateLink: privateDnsForPrivateEndpointNicTemplateLink
    privateDnsForPrivateEndpointIpConfigTemplateLink: privateDnsForPrivateEndpointIpConfigTemplateLink
  }
}

module ledger_digestStorageName '?' /*TODO: replace with correct path to [parameters('sqlLedgerTemplateLink')]*/ = if (enableDigestStorage == 'Enabled') {
  name: 'ledger-${digestStorageName}'
  scope: resourceGroup(subscriptionId, resourceGroupName)
  params: {
    enableDigestStorage: enableDigestStorage
    digestStorageOption: digestStorageOption
    digestStorageName: digestStorageName
    blobStorageContainerName: blobStorageContainerName
    retentionDays: retentionDays
    retentionPolicy: retentionPolicy
    serverName: serverName
    digestAccountResourceGroup: digestAccountResourceGroup
    databaseName: databaseName
    serverLocation: location
    digestRegion: digestRegion
    storageAccountdigestRegion: storageAccountdigestRegion
    isNewDigestLocation: isNewDigestLocation
    isPermissionAssigned: isPermissionAssigned
  }
  dependsOn: [
    serverName_resource
    serverName_databaseName
  ]
}
