param reference_concat_Microsoft_Resources_deployments_variables_privateEndpointTemplateName_outputs_networkInterfaceId_value object
param variables_privateEndpointVnetId ? /* TODO: fill in correct type */
param variables_deploymentTemplateApi ? /* TODO: fill in correct type */
param privateLinkPrivateDnsZoneFQDN string
param privateEndpointDnsRecordUniqueId string
param privateDnsForPrivateEndpointTemplateLink string
param enablePrivateEndpoint bool
param privateDnsForPrivateEndpointNicTemplateLink string
param privateDnsForPrivateEndpointIpConfigTemplateLink string

resource privateLinkPrivateDnsZoneFQDN_resource 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateLinkPrivateDnsZoneFQDN
  location: 'global'
  tags: {
  }
  properties: {
  }
}

resource privateLinkPrivateDnsZoneFQDN_variables_privateEndpointVnetId 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  parent: privateLinkPrivateDnsZoneFQDN_resource
  name: '${uniqueString(variables_privateEndpointVnetId)}'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: variables_privateEndpointVnetId
    }
    registrationEnabled: false
  }
}

module EndpointDnsRecords_privateEndpointDnsRecordUniqueId '?' /*TODO: replace with correct path to [parameters('privateDnsForPrivateEndpointTemplateLink')]*/ = {
  name: 'EndpointDnsRecords-${privateEndpointDnsRecordUniqueId}'
  params: {
    privateDnsName: privateLinkPrivateDnsZoneFQDN
    privateEndpointNicResourceId: (enablePrivateEndpoint ? reference_concat_Microsoft_Resources_deployments_variables_privateEndpointTemplateName_outputs_networkInterfaceId_value.outputs.networkInterfaceId.value : '')
    nicRecordsTemplateUri: privateDnsForPrivateEndpointNicTemplateLink
    ipConfigRecordsTemplateUri: privateDnsForPrivateEndpointIpConfigTemplateLink
    uniqueId: privateEndpointDnsRecordUniqueId
    existingRecords: {
    }
  }
  dependsOn: [
    privateLinkPrivateDnsZoneFQDN_resource
  ]
}