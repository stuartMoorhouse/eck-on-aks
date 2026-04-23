#!/usr/bin/env bash
# Verify Azure CLI login and export Cloudflare credentials as TF vars.
# Run this before terraform apply (or source it: . scripts/get-secrets.sh).

set -euo pipefail

REQUIRED_SUBSCRIPTION="YOUR_SUBSCRIPTION_ID"

echo "Checking Azure CLI login..."
CURRENT=$(az account show --query id -o tsv 2>/dev/null || true)

if [[ -z "$CURRENT" ]]; then
  echo "Not logged in. Running az login..."
  az login
  CURRENT=$(az account show --query id -o tsv)
fi

if [[ "$CURRENT" != "$REQUIRED_SUBSCRIPTION" ]]; then
  echo "Wrong subscription ($CURRENT). Switching to $REQUIRED_SUBSCRIPTION..."
  az account set --subscription "$REQUIRED_SUBSCRIPTION"
fi

echo "Logged in. Subscription: $(az account show --query name -o tsv) ($REQUIRED_SUBSCRIPTION)"

# Cloudflare credentials — read from shell env vars set in ~/.zshrc
if [[ -z "${CLOUDFLARE_KEY:-}" ]]; then
  echo "ERROR: CLOUDFLARE_KEY is not set. Export it in your environment before running."
  exit 1
fi
if [[ -z "${CLOUDFLARE_ZONE:-}" ]]; then
  echo "ERROR: CLOUDFLARE_ZONE is not set. Export it in your environment before running."
  exit 1
fi

export TF_VAR_cloudflare_api_token="$CLOUDFLARE_KEY"
export TF_VAR_cloudflare_zone_id="$CLOUDFLARE_ZONE"

echo "Cloudflare credentials exported as TF_VAR_cloudflare_api_token and TF_VAR_cloudflare_zone_id."
echo "Ready to run: cd infra && terraform init && terraform apply"
