# Read-only access to campaign-center application secrets (KV v2).
# Mounted at: secret/data/campaign-center/<env>/<service>
path "secret/data/{{ vault_secret_prefix }}/*" {
  capabilities = ["read"]
}

path "secret/metadata/{{ vault_secret_prefix }}/*" {
  capabilities = ["list", "read"]
}
