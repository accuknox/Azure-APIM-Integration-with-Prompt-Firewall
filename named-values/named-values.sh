#!/usr/bin/env bash
set -e

RESOURCE_GROUP=$1
APIM_SERVICE_NAME=$2

if [ -z "$RESOURCE_GROUP" ] || [ -z "$APIM_SERVICE_NAME" ]; then
  echo "Usage: $0 <RESOURCE_GROUP> <APIM_SERVICE_NAME>"
  exit 1
fi

echo -n "Enter AccuKnox LLM Defence Token: "
read -s ACCUKNOX_TOKEN
echo ""

if [ -z "$ACCUKNOX_TOKEN" ]; then
  echo "Error: Token cannot be empty"
  exit 1
fi

az apim nv create \
  --resource-group "$RESOURCE_GROUP" \
  --service-name "$APIM_SERVICE_NAME" \
  --named-value-id LLM_DEFENCE_TOKEN3 \
  --display-name "AccuKnox-LLM-Defence-Token3" \
  --secret true \
  --value "$ACCUKNOX_TOKEN"

echo "✅ Named Value LLM_DEFENCE_TOKEN created/updated successfully"
