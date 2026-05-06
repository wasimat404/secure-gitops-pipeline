# Vault policy: secure-app-read
#
# Grants the app's Kubernetes ServiceAccount read access to its secret path
# in the KV v2 mount, and nothing else. Apply with:
#
#   vault policy write secure-app-read vault/policy.hcl
#

# Read the secret value.
path "secret/data/secure-app/db" {
  capabilities = ["read"]
}

# Read metadata (needed by some KV v2 clients).
path "secret/metadata/secure-app/db" {
  capabilities = ["read"]
}
