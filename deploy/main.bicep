


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
param location string = 'westus3'

param environmentName string = 'e4k-cloud-edge-sample-${uniqueString(resourceGroup().id)}'
// Event Hub settings
param eventHubNamespace string = 'eh-${uniqueString(resourceGroup().id)}'
param eventHubD2CName string = 'e4k-d2c'
param eventHubC2DName string = 'e4k-c2d'
param eventHubD2CConsumerGroup string = 'aca-d2c'
param eventHubC2DConsumerGroup string = 'aca-c2d'
param storageAccountName string = 'stor${uniqueString(resourceGroup().id)}'

// Container Apps settings
param eventHubImage string = 'veyalla/eh-test:0.0.2'



var eventHubD2CConnectionSecretName = 'event-hub-d2c-connection-string'
var eventHubC2DConnectionSecretName = 'event-hub-c2d-connection-string'
var storageConnectionSecretName = 'storage-connection-string'
var storageLeaseBlobName = 'aca-leases'

// Container Apps Environment (environment.bicep)
module environment 'environment.bicep' = {
  name: 'container-app-environment'
  params: {
    environmentName: environmentName
    location: location
  }
}


module eventHub 'eventhub.bicep' = {
  name: 'eventhub'
  params: {
    eventHubNamespaceName: eventHubNamespace
    eventHubD2CName: eventHubD2CName
    eventHubC2DName: eventHubC2DName
    consumerGroupD2CName: eventHubD2CConsumerGroup
    consumerGroupC2DName: eventHubC2DConsumerGroup
    storageAccountName: storageAccountName
    storageLeaseBlobName: storageLeaseBlobName
  }
}

resource ehContainerApp 'Microsoft.App/containerApps@2022-01-01-preview' = {
  name: 'event-hub-app'
  location: location
  properties: {
    managedEnvironmentId: environment.outputs.environmentId
    configuration: {
      activeRevisionsMode: 'single'
      secrets: [
        {
          name: eventHubC2DConnectionSecretName
          value: eventHub.outputs.eventHubC2DConnectionString
        }
        {
          name: eventHubD2CConnectionSecretName
          value: eventHub.outputs.eventHubD2CConnectionString
        }
        {
          name: storageConnectionSecretName
          value: eventHub.outputs.storageConnectionString
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
