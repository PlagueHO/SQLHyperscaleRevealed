param name string
param location string
param addressSpace string
param appSubnetAddressSpace string
param dataSubnetAddressSpace string
param managementSubnetAddressSpace string
param azureBastionSubnetAddressSpace string
param environment string = 'SQL Hyperscale Revealed demo'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    subnets: [
      {
        name: 'app_subnet'
        properties: {
          addressPrefix: appSubnetAddressSpace
        }
      }
      {
        name: 'data_subnet'
        properties: {
          addressPrefix: dataSubnetAddressSpace
        }
      }
      {
        name: 'management_subnet'
        properties: {
          addressPrefix: managementSubnetAddressSpace
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: azureBastionSubnetAddressSpace
        }
      }
    ]
  }
  tags: {
    Environment: environment
  }
}

output vnetId string = virtualNetwork.id
output appSubnetId string = virtualNetwork.properties.subnets[0].id
output dataSubnetId string = virtualNetwork.properties.subnets[1].id
output managementSubnetId string = virtualNetwork.properties.subnets[2].id
output azureBastionSubnetId string = virtualNetwork.properties.subnets[1].id
