# Azure Container Apps Event Hub sample (dotnet)


### Deploy via Bicep


1. Clone this repo and navigate to the folder
2. Run the following CLI command (with appropriate values for $variables)
  ```cli
  az group create -n $resourceGroup -l $location
  az deployment group create -g $resourceGroup -f ./deploy/main.bicep 
  ```

### Acknowledgments
Mostly lift and shift from https://github.com/jeffhollan/container-apps-dotnet-eventing
