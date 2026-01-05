#!/usr/bin/env bash
set -e

source .env

echo "Setting subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

echo "Deploying API & operation..."
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file bicep/apim-api.bicep \
  --parameters \
    apimServiceName="$APIM_SERVICE_NAME" \
    apiId="$API_ID" \
    apiDisplayName="$API_DISPLAY_NAME" \
    apiPath="$API_PATH" \
    backendUrl="$API_BACKEND_URL" \
    operationId="$OPERATION_ID" \
    operationDisplayName="$OPERATION_DISPLAY_NAME" \
    operationMethod="$OPERATION_METHOD" \
    operationUrlTemplate="$OPERATION_URL_TEMPLATE"

echo "Creating / updating Named Values..."


echo "NOTE: Secrets must be created once manually or via secure CI:"
echo " - LLM_DEFENCE_TOKEN"

echo "Applying combined policy..."
az rest \
  --method PUT \
  --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_SERVICE_NAME/apis/$API_ID/operations/$OPERATION_ID/policies/policy?api-version=2022-08-01" \
  --headers "Content-Type=application/vnd.ms-azure-apim.policy+xml" \
  --body @policies/policy.xml




echo "Deployment completed successfully."
