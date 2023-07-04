#!/usr/bin/env bash

deployment="mbright-bicep"
resource_group="mbright-bicep"
template="main.bicep"
parameters="parameters.json"

az deployment group create \
  --name "$deployment" \
  --resource-group "$resource_group" \
  --template-file "$template" \
  --parameters "$parameters" 
