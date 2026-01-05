#!/usr/bin/env bash
set -e

# ----------------------------------
# Load .env
# ----------------------------------
if [ ! -f .env ]; then
  echo "❌ .env file not found"
  exit 1
fi

set -o allexport
source .env
set +o allexport


# ----------------------------------
# Prompt for AccuKnox token (ONLY secret)
# ----------------------------------
echo -n "🔐 Enter AccuKnox LLM Defence Token: "
read -s ACCUKNOX_TOKEN
echo ""

if [ -z "$ACCUKNOX_TOKEN" ]; then
  echo "❌ AccuKnox token cannot be empty"
  exit 1
fi

# ----------------------------------
# Set subscription
# ----------------------------------
echo "🔑 Setting subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

# ----------------------------------
# Create / Update Named Value
# ----------------------------------
echo "🔐 Creating / updating APIM Named Value..."

az apim nv create \
  --resource-group "$RESOURCE_GROUP" \
  --service-name "$APIM_SERVICE_NAME" \
  --named-value-id LLM_DEFENCE_TOKEN \
  --display-name "AccuKnox-LLM-Defence-Token" \
  --secret true \
  --value "$ACCUKNOX_TOKEN"

# ----------------------------------
# Deploy API & operation
# ----------------------------------
echo "🚀 Deploying API & operation..."

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

# ----------------------------------
# Apply policy (consistent API version)
# ----------------------------------
echo "📜 Applying policy..."

az rest \
  --method PUT \
  --uri "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_SERVICE_NAME/apis/$API_ID/operations/$OPERATION_ID/policies/policy?api-version=2022-08-01" \
  --headers "Content-Type=application/vnd.ms-azure-apim.policy+xml" \
  --body @policies/policy.xml

echo "✅ Deployment completed successfully"
