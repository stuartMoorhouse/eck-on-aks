#!/usr/bin/env bash
# Fetch ECK-generated credentials from Kubernetes secrets and print connection details.
# Run after terraform apply completes.

set -euo pipefail

NAMESPACE="elastic-system"
ES_SECRET="elasticsearch-es-elastic-user"

echo "Fetching elastic user password..."
ELASTIC_PASSWORD=$(kubectl get secret "$ES_SECRET" -n "$NAMESPACE" -o go-template='{{.data.elastic | base64decode}}')

echo ""
echo "Connection Details"
echo "=================="
echo "Kibana:        https://kibana.eck-on-aks.cascavel-security.net"
echo "Elasticsearch: https://elasticsearch.eck-on-aks.cascavel-security.net"
echo "Fleet Server:  https://fleet.eck-on-aks.cascavel-security.net"
echo "APM Server:    https://apm.eck-on-aks.cascavel-security.net"
echo ""
echo "Username: elastic"
echo "Password: $ELASTIC_PASSWORD"
