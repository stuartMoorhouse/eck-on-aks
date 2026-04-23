#!/usr/bin/env bash
# Full deploy: two-phase terraform apply to handle the DNS zone -> Cloudflare NS delegation
# dependency, then runs configure.sh to wait for ECK components to be healthy.
#
# Prerequisites — set these in your environment before running:
#   export CLOUDFLARE_KEY=<api-token>
#   export CLOUDFLARE_ZONE=<zone-id>
#
# ARM_* env vars are unset so the azurerm provider uses Azure CLI auth
# rather than a service principal from another project's environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$SCRIPT_DIR/../infra"

# Verify required tools
for tool in az terraform kubectl; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: '$tool' is not installed."
    exit 1
  fi
done

# Verify required environment variables are set
missing=()
[[ -z "${CLOUDFLARE_KEY:-}" ]]  && missing+=("CLOUDFLARE_KEY")
[[ -z "${CLOUDFLARE_ZONE:-}" ]] && missing+=("CLOUDFLARE_ZONE")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Required environment variables are not set: ${missing[*]}"
  echo "  export CLOUDFLARE_KEY=<cloudflare-api-token>"
  echo "  export CLOUDFLARE_ZONE=<cloudflare-zone-id>"
  exit 1
fi

# Set up environment: export Cloudflare TF_VARs, verify Azure subscription.
# Must be sourced (not run as subprocess) to propagate exports.
# shellcheck source=scripts/get-secrets.sh
source "$SCRIPT_DIR/get-secrets.sh"

# Clear any ARM_* service principal vars that would override CLI auth
unset ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_SUBSCRIPTION_ID ARM_TENANT_ID 2>/dev/null || true

cd "$INFRA_DIR"

echo ""
echo "Phase 1: Init"
echo "============="
terraform init -input=false

echo ""
echo "Phase 2: AKS cluster + DNS zone"
echo "================================"
terraform apply -input=false -auto-approve \
  -target=azurerm_resource_group.main \
  -target=azurerm_kubernetes_cluster.main \
  -target=azurerm_dns_zone.main

echo ""
echo "Phase 3: Full apply (Cloudflare NS delegation, cert-manager, ECK)"
echo "=================================================================="
terraform apply -input=false -auto-approve

echo ""
echo "Phase 4: Configure and wait for ECK health"
echo "==========================================="
source "$SCRIPT_DIR/configure.sh"
