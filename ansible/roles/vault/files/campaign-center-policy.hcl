# Read-only access to campaign-center application secrets (KV v2).
# Mounted at: secret/data/campaign-center/<env>/<service>
path "secret/data/campaign-center/*" {
  capabilities = ["read"]
}

path "secret/metadata/campaign-center/*" {
  capabilities = ["list", "read"]
}
