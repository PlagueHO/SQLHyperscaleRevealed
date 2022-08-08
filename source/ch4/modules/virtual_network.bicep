param name string
param location string
param addressSpace string
param appSubnetAddressSpace string
param dataSubnetAddressSpace string
param environment string = 'SQL Hyperscale Reveaeled demo'

resource virtual_network 'Microsoft.Network/virtualNetworks@2022-01-01' = {
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
    ]
  }
  tags: {
    Environment: environment
  }
}

