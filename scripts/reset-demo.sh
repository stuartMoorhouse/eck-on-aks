#!/usr/bin/env bash
# Reset the ECK stack without destroying AKS infrastructure.
# Deletes all ECK resources, waits for pods to terminate, then re-applies from config/.
# WARNING: This deletes all Elasticsearch data.

set -euo pipefail

NAMESPACE="elastic-system"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(cd "$SCRIPT_DIR/../config" && pwd)"

# Verify required tools are present
if ! command -v kubectl &>/dev/null; then
  echo "ERROR: 'kubectl' not found. Install it or run 'az aks install-cli'."
  exit 1
fi

# Confirm destructive action
echo "WARNING: This will delete all ECK resources in namespace '$NAMESPACE', including all Elasticsearch data."
read -p "Type 'yes' to confirm: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# Delete all ECK resources
echo "Deleting ECK resources..."
kubectl delete elasticsearch,kibana,agent,apmserver --all -n "$NAMESPACE" --ignore-not-found=true

# Wait for ECK pods to terminate
echo "Waiting for ECK pods to terminate..."
while true; do
  POD_COUNT=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$POD_COUNT" -eq 0 ]]; then
    break
  fi
  echo "  $POD_COUNT pod(s) still running — waiting 10s..."
  sleep 10
done
echo "All ECK pods terminated."

# Re-apply ECK resources from config/
echo "Applying ECK resources from config/..."
kubectl apply \
  -f "$CONFIG_DIR/elasticsearch.yaml" \
  -f "$CONFIG_DIR/kibana.yaml" \
  -f "$CONFIG_DIR/fleet-server.yaml" \
  -f "$CONFIG_DIR/apm-server.yaml"
echo "ECK resources applied."

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
