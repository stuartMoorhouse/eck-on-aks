#!/usr/bin/env bash
# Post-deploy configuration script. Run after terraform apply completes.
# Merges AKS credentials and waits for all ECK components to reach healthy status.

set -euo pipefail

RESOURCE_GROUP="eck-on-aks-rg"
CLUSTER_NAME="eck-on-aks-aks"
NAMESPACE="elastic-system"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify required tools are present
if ! command -v az &>/dev/null; then
  echo "ERROR: 'az' (Azure CLI) not found. Install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
  exit 1
fi
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: 'kubectl' not found. Install it or run 'az aks install-cli'."
  exit 1
fi

# Merge AKS credentials
echo "Merging AKS credentials for cluster: $CLUSTER_NAME..."
if ! az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing; then
  echo "ERROR: Failed to get AKS credentials."
  echo "  - Verify the cluster exists: az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME"
  echo "  - Verify you are logged in: az account show"
  exit 1
fi
echo "Credentials merged."

# Wait for Elasticsearch to reach green health
echo "Waiting for Elasticsearch to be healthy (up to 600s)..."
kubectl wait elasticsearch/elasticsearch \
  -n "$NAMESPACE" \
  --for=jsonpath='{.status.health}'=green \
  --timeout=600s
echo "Elasticsearch is green."

# Wait for Kibana to reach green health
echo "Waiting for Kibana to be ready (up to 300s)..."
kubectl wait kibana/kibana \
  -n "$NAMESPACE" \
  --for=jsonpath='{.status.health}'=green \
  --timeout=300s
echo "Kibana is green."

# Wait for Fleet Server to reach green health
echo "Waiting for Fleet Server to be ready (up to 300s)..."
kubectl wait agent/fleet-server \
  -n "$NAMESPACE" \
  --for=jsonpath='{.status.health}'=green \
  --timeout=300s
echo "Fleet Server is green."

# Print credentials
echo ""
"$SCRIPT_DIR/get-creds.sh"

# Print access URLs
echo ""
echo "Access URLs"
echo "==========="
echo "Kibana: https://kibana.eck-on-aks.cascavel-security.net"
echo "Fleet:  https://fleet.eck-on-aks.cascavel-security.net"
echo "APM:    https://apm.eck-on-aks.cascavel-security.net"
