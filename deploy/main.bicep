
@allowed([
  'eastasia'
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'northeurope'
  'westeurope'
  'francecentral'
  'germanywestcentral'
  'japaneast'
  'koreacentral'
  'norwayeast'
  'uksouth'
  'centralus'
  'eastus'
  'eastus2'
  'northcentralus'
  'southcentralus'
  'westus'
  'westus3'
])
@description('Location for cloud resources')
param location string = 'westus3'

var endpoint = '${eventHubNamespace.id}/AuthorizationRules/RootManageSharedAccessKey'



param environmentName string = 'e4k-cloud-edge-sample-${uniqueString(resourceGroup().id)}'
// Event Hub settings
param eventHubNamespaceName string = 'eh-${uniqueString(resourceGroup().id)}'
param eventHubD2CName string = 'e4k-d2c'
param eventHubC2DName string = 'e4k-c2d'
param eventHubD2CConsumerGroup string = 'aca-d2c'
param eventHubC2DConsumerGroup string = 'aca-c2d'
param storageAccountName string = 'stor${uniqueString(resourceGroup().id)}'

param eventHubImage string = 'veyalla/eh-test:0.0.2'
param eventHubSku string = 'Standard'
param storageLeaseBlobName string = 'aca-leases'

var eventHubD2CConnectionSecretName = 'event-hub-d2c-connection-string'
var eventHubC2DConnectionSecretName = 'event-hub-c2d-connection-string'
var storageConnectionSecretName = 'storage-connection-string'

param logAnalyticsWorkspaceName string = 'logs-${environmentName}'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-03-01-preview' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  })
}

resource managedEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

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
  name: '${eventHubD2C.name}/${eventHubD2CConsumerGroup}'
  properties: {}
}

resource consumerGroupC2D 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2017-04-01' = {
  name: '${eventHubC2D.name}/${eventHubC2DConsumerGroup}'
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


resource ehContainerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'event-hub-app'
  location: location
  properties: {
    managedEnvironmentId:  managedEnv.id
    configuration: {
      activeRevisionsMode: 'single'
      secrets: [
        {
          name: eventHubC2DConnectionSecretName
          value: '${listKeys(endpoint, eventHubC2D.apiVersion).primaryConnectionString};EntityPath=${eventHubC2DName}'
        }
        {
          name: eventHubD2CConnectionSecretName
          value: '${listKeys(endpoint, eventHubD2C.apiVersion).primaryConnectionString};EntityPath=${eventHubD2CName}'
        }
        {
          name: storageConnectionSecretName
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
      ]
    }
    template: {
      containers: [
        {
          image: eventHubImage
          name: 'event-hub-app'
          env: [
            {
              name: 'EVENTHUB_C2D_CONNECTION_STRING'
              secretRef: eventHubC2DConnectionSecretName
            }
            {
              name: 'EVENTHUB_D2C_CONNECTION_STRING'
              secretRef: eventHubD2CConnectionSecretName
            }
            {
              name: 'EVENTHUB_D2C_NAME'
              value: eventHubD2CName
            }
	          {
              name: 'EVENTHUB_C2D_NAME'
              value: eventHubC2DName
            }
            {
              name: 'EVENTHUB_D2C_CONSUMER_GROUP'
              value: eventHubD2CConsumerGroup
            }
            {
              name: 'EVENTHUB_C2D_CONSUMER_GROUP'
              value: eventHubC2DConsumerGroup
            }
            {
              name: 'STORAGE_CONNECTION_STRING'
              secretRef: storageConnectionSecretName
            }
            {
              name: 'STORAGE_BLOB_NAME'
              value: storageLeaseBlobName
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
}
