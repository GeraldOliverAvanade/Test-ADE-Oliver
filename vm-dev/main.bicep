@description('Environment name used as a prefix for resources')
param envName string

@description('VNET name')
param vnetName string

@description('VNET address space in CIDR format (e.g., 10.10.0.0/16)')
param vnetAddressPrefix string

@description('Subnet name')
param subnetName string

@description('Subnet address prefix in CIDR format (e.g., 10.10.1.0/24)')
param subnetAddressPrefix string

@description('Azure region for deployment')
param location string = resourceGroup().location

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
        }
      }
    ]
  }
}

output deployedVnetName string = vnet.name
output deployedSubnetName string = subnetName
