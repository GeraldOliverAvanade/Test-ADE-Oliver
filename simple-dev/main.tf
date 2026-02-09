@description('Environment name used as a prefix for resources')
param envName string

@description('Azure region for deployment')
param location string = resourceGroup().location

// Storage account names: 3-24 chars, lowercase letters and numbers only
var base = toLower(replace(envName, '-', ''))
var saNameRaw = '${base}sa'
var saName = take(saNameRaw, 24)

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: saName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}
