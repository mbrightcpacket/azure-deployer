#!/usr/bin/env bash

deployment="mbright-bicep"
resource_group="mbright-bicep"
template="main.bicep"
parameters="parameters.json"
location="eastus2"

az group create --name "$resource_group" --location "$location"
# az deployment group create --resource-group exampleRG --template-file main.bicep --parameters appInsightsLocation=<app-location>

az deployment group create \
  --name "$deployment" \
  --resource-group "$resource_group" \
  --template-file "$template" \
  --parameters "$parameters" 
