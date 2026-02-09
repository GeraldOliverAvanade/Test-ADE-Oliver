@description('Environment name used as a prefix for resources')
param envName string

@description('Azure region for deployment (empty = RG location)')
param location string = resourceGroup().location

@description('VNet name (empty = auto from envName)')
param vnetName string = ''

@description('VNet CIDR, e.g. 10.10.0.0/16')
param vnetAddressSpace string

@description('Subnets array. Each item supports: name, addressPrefix, privateEndpointNetworkPolicies (Enabled/Disabled), privateLinkServiceNetworkPolicies (Enabled/Disabled)')
param subnets array

@description('Optional custom DNS servers. Empty means Azure default.')
param dnsServers array = []

@description('Optional tags object')
param tags object = {}

var effectiveVnetName = empty(vnetName) ? toLower('${envName}-vnet') : vnetName

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: effectiveVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    dhcpOptions: empty(dnsServers) ? null : {
      dnsServers: dnsServers
    }
  }
}

resource vnetSubnets 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = [for s in subnets: {
  parent: vnet
  name: s.name
  properties: {
    addressPrefix: s.addressPrefix
    privateEndpointNetworkPolicies: contains(s, 'privateEndpointNetworkPolicies') ? s.privateEndpointNetworkPolicies : 'Enabled'
    privateLinkServiceNetworkPolicies: contains(s, 'privateLinkServiceNetworkPolicies') ? s.privateLinkServiceNetworkPolicies : 'Enabled'
  }
}]

output vnetId string = vnet.id
output vnetNameOut string = vnet.name
output subnetIds array = [for sn in vnetSubnets: sn.id]
