#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Wires Vault to a Kubernetes cluster so workloads can authenticate using
# their ServiceAccount tokens — no static Vault tokens stored anywhere.
#
# Run this AFTER:
#   - Vault is installed and you're logged in (VAULT_ADDR + VAULT_TOKEN set)
#   - The `secure-app` namespace and ServiceAccount exist in the cluster
#
# Idempotent — safe to re-run.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

: "${VAULT_ADDR:?VAULT_ADDR must be set}"
: "${KUBE_HOST:?KUBE_HOST must be set (e.g. https://kubernetes.default.svc)}"

POLICY_NAME="secure-app-read"
ROLE_NAME="secure-app"
SA_NAME="secure-app"
NAMESPACE="secure-app"
SECRET_PATH="secret/secure-app/db"

# 1. Enable KV v2 at secret/ if not already enabled.
vault secrets enable -path=secret -version=2 kv 2>/dev/null \
  || echo "KV v2 already enabled at secret/"

# 2. Write a sample DB credential. In real life this is rotated/managed
#    out-of-band; never commit real values to a repo.
vault kv put "$SECRET_PATH" \
  username="app_user" \
  password="$(openssl rand -base64 24)"

# 3. Apply the read-only policy.
vault policy write "$POLICY_NAME" "$(dirname "$0")/policy.hcl"

# 4. Enable the Kubernetes auth method.
vault auth enable kubernetes 2>/dev/null \
  || echo "kubernetes auth already enabled"

# 5. Tell Vault how to reach the cluster API. Vault will validate
#    ServiceAccount tokens against this kube-apiserver.
vault write auth/kubernetes/config \
  kubernetes_host="$KUBE_HOST"

# 6. Bind the SA → policy. Only pods running under this SA in this namespace
#    can authenticate to Vault and only get the policy attached.
vault write "auth/kubernetes/role/$ROLE_NAME" \
  bound_service_account_names="$SA_NAME" \
  bound_service_account_namespaces="$NAMESPACE" \
  policies="$POLICY_NAME" \
  ttl=1h

echo "✓ Vault wired up. Role '$ROLE_NAME' in namespace '$NAMESPACE' can read $SECRET_PATH."
