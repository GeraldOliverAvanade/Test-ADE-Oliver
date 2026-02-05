param envName string
param location string = 'japaneast'

resource sa 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: toLower('${envName}sa')
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}
