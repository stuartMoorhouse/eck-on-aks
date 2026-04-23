#!/usr/bin/env bash
# Registers the Azure Blob snapshot repository and creates an SLM policy.
# Run after terraform apply + configure.sh (cluster must be green).

set -euo pipefail

NAMESPACE="elastic-system"
ES_NAME="elasticsearch"
CONTAINER="elasticsearch-snapshots"
REPO_NAME="azure-backup"
POLICY_NAME="daily-snapshots"

# Fetch elastic user credentials
ELASTIC_PASSWORD=$(kubectl get secret \
  "${ES_NAME}-es-elastic-user" \
  -n "${NAMESPACE}" \
  -o jsonpath='{.data.elastic}' | base64 --decode)

# Resolve the Elasticsearch service hostname
ES_HOST="${ES_NAME}-es-http.${NAMESPACE}.svc.cluster.local"

# Helper: call ES API
es_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local args=(-s -k -u "elastic:${ELASTIC_PASSWORD}" -X "${method}"
    "https://${ES_HOST}:9200${path}"
    -H "Content-Type: application/json")
  if [[ -n "${body}" ]]; then
    args+=(-d "${body}")
  fi
  curl "${args[@]}"
}

echo "Registering snapshot repository '${REPO_NAME}'..."
es_api PUT "/_snapshot/${REPO_NAME}" "$(cat <<EOF
{
  "type": "azure",
  "settings": {
    "client": "default",
    "container": "${CONTAINER}",
    "base_path": "backups"
  }
}
EOF
)"
echo ""

echo "Verifying repository..."
es_api GET "/_snapshot/${REPO_NAME}" ""
echo ""

echo "Creating SLM policy '${POLICY_NAME}'..."
es_api PUT "/_slm/policy/${POLICY_NAME}" "$(cat <<EOF
{
  "schedule": "0 30 1 * * ?",
  "name": "<daily-snapshot-{now/d}>",
  "repository": "${REPO_NAME}",
  "config": {
    "indices": ["*"],
    "include_global_state": false
  },
  "retention": {
    "expire_after": "30d",
    "min_count": 5,
    "max_count": 50
  }
}
EOF
)"
echo ""

echo "Snapshot repository and SLM policy configured."
echo "  Repository : ${REPO_NAME} (Azure container: ${CONTAINER})"
echo "  SLM policy : ${POLICY_NAME} (daily at 01:30, 30-day retention)"
echo ""
echo "Take a manual snapshot now to verify:"
echo "  kubectl exec -n ${NAMESPACE} \$(kubectl get pods -n ${NAMESPACE} -l elasticsearch.k8s.elastic.co/cluster-name=${ES_NAME} -o name | head -1) -- curl -sk -u elastic:\${ELASTIC_PASSWORD} -X POST 'https://localhost:9200/_slm/policy/${POLICY_NAME}/_execute'"
