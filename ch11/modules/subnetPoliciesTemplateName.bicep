param variables_privateEndpointApi ? /* TODO: fill in correct type */
param privateEndpointVnetName string
param privateEndpointSubnetName string
param privateEndpointLocation string

resource privateEndpointVnetName_privateEndpointSubnetName 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' = {
  name: '${privateEndpointVnetName}/${privateEndpointSubnetName}'
  location: privateEndpointLocation
  properties: {
    privateEndpointNetworkPolicies: 'Disabled'
    provisioningState: 'Succeeded'
    addressPrefix: '10.0.2.0/24'
    delegations: []
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}
