@description('Environment name used as a prefix for resources')
param envName string

@description('Azure region for deployment (empty = RG location)')
param location string = resourceGroup().location

@description('VNet name (empty = auto from envName)')
param vnetName string = ''

@description('VNet CIDR, e.g. 10.10.0.0/16')
param vnetAddressSpace string

@description('Subnets array. Each item supports: name, addressPrefix, privateEndpointNetworkPolicies (Enabled/Disabled), privateLinkServiceNetworkPolicies (Enabled/Disabled), nsgRules (optional array)')
param subnets array

@description('Optional custom DNS servers. Empty means Azure default.')
param dnsServers array = []

@description('Enable DDoS protection plan (default false). If true, requires ddosPlanResourceId.')
param enableDdosProtection bool = false

@description('DDoS plan resource ID (required if enableDdosProtection = true)')
param ddosPlanResourceId string = ''

@description('Optional tags object')
param tags object = {}

var effectiveVnetName = empty(vnetName) ? toLower('${envName}-vnet') : vnetName

// Optional DDoS plan reference (existing)
resource ddosPlan 'Microsoft.Network/ddosProtectionPlans@2023-11-01' existing = if (enableDdosProtection) {
  scope: subscription()
  name: last(split(ddosPlanResourceId, '/'))
}

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
    enableDdosProtection: enableDdosProtection
    ddosProtectionPlan: enableDdosProtection ? {
      id: ddosPlanResourceId
    } : null
  }
}

// If you want NSGs per subnet (optional), define rules per subnet item as `nsgRules`.
// nsgRules example item:
// { "name":"Allow-HTTPS-In", "priority":100, "direction":"Inbound", "access":"Allow", "protocol":"Tcp",
//   "sourceAddressPrefix":"*", "sourcePortRange":"*", "destinationAddressPrefix":"*", "destinationPortRange":"443" }

resource subnetNsgs 'Microsoft.Network/networkSecurityGroups@2023-11-01' = [for s in subnets: if (!empty(s.nsgRules)) {
  name: toLower('${effectiveVnetName}-${s.name}-nsg')
  location: location
  tags: tags
  properties: {
    securityRules: [for r in s.nsgRules: {
      name: r.name
      properties: {
        priority: r.priority
        direction: r.direction
        access: r.access
        protocol: r.protocol
        sourcePortRange: r.sourcePortRange
        destinationPortRange: r.destinationPortRange
        sourceAddressPrefix: r.sourceAddressPrefix
        destinationAddressPrefix: r.destinationAddressPrefix
      }
    }]
  }
}]

resource vnetSubnets 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = [for (s, i) in subnets: {
  parent: vnet
  name: s.name
  properties: {
    addressPrefix: s.addressPrefix

    // Useful for PE subnet: set "Disabled" to allow private endpoints
    privateEndpointNetworkPolicies: contains(s, 'privateEndpointNetworkPolicies') ? s.privateEndpointNetworkPolicies : 'Enabled'
    privateLinkServiceNetworkPolicies: contains(s, 'privateLinkServiceNetworkPolicies') ? s.privateLinkServiceNetworkPolicies : 'Enabled'

    networkSecurityGroup: !empty(s.nsgRules) ? {
      id: subnetNsgs[i].id
    } : null
  }
}]

output vnetId string = vnet.id
output vnetNameOut string = vnet.name
output subnetIds array = [for sn in vnetSubnets: sn.id]
