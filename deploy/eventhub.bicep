param location string = resourceGroup().location
param eventHubSku string = 'Standard'

param eventHubNamespaceName string
param eventHubD2CName string
param eventHubC2DName string
param consumerGroupD2CName string
param consumerGroupC2DName string
param storageAccountName string
param storageLeaseBlobName string = 'aca-leases'

var endpoint = '${eventHubNamespace.id}/AuthorizationRules/RootManageSharedAccessKey'



resource eventHubNamespace 'Microsoft.EventHub/namespaces@2018-01-01-preview' = {
  dependsOn: [
    container
  ]
  name: eventHubNamespaceName
  location: location
  sku: {
    name: eventHubSku
    tier: eventHubSku
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
  }
}

resource eventHubD2C 'Microsoft.EventHub/namespaces/eventhubs@2017-04-01' = {
  name: '${eventHubNamespace.name}/${eventHubD2CName}'
  properties: {
    messageRetentionInDays: 7
    partitionCount: 1
  }
}

resource eventHubC2D 'Microsoft.EventHub/namespaces/eventhubs@2017-04-01' = {
  name: '${eventHubNamespace.name}/${eventHubC2DName}'
  properties: {
    messageRetentionInDays: 7
    partitionCount: 1
  }
}

resource consumerGroupD2C 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2017-04-01' = {
  name: '${eventHubD2C.name}/${consumerGroupD2CName}'
  properties: {}
}

resource consumerGroupC2D 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2017-04-01' = {
  name: '${eventHubC2D.name}/${consumerGroupC2DName}'
  properties: {}
}

// Storage Account for consumer leases
resource storageAccount 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-05-01' = {
    name:  '${storageAccount.name}/default/${storageLeaseBlobName}'
    properties: {
      publicAccess: 'None'
      metadata: {}
    }
}

output eventHubD2CConnectionString string = '${listKeys(endpoint, eventHubD2C.apiVersion).primaryConnectionString};EntityPath=${eventHubD2CName}'
output eventHubC2DConnectionString string = '${listKeys(endpoint, eventHubC2D.apiVersion).primaryConnectionString};EntityPath=${eventHubC2DName}'
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
