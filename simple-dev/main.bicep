@description('Environment name used as a prefix for resources')
param envName string

@description('Azure region for deployment')
param location string = resourceGroup().location

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: toLower('${envName}sa')
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}
