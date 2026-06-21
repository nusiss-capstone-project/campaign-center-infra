# Vault & External Secrets — campaign-center

Central secret management for the campaign-center platform on k3s (Alibaba Cloud ECS).

**This repository** deploys Vault and External Secrets Operator (ESO). **Application manifests** (Deployments, ExternalSecrets, ArgoCD Applications) live in separate GitOps repositories.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────┐
│  GitOps repo (ArgoCD)                                                   │
│  ExternalSecret → references ClusterSecretStore "vault-backend"         │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  k3s cluster                                                            │
│                                                                         │
│  namespace: external-secrets                                            │
│  ┌──────────────────────┐      Kubernetes JWT auth                    │
│  │ External Secrets     │──────────────────────────────┐              │
│  │ Operator             │                              │              │
│  └──────────┬───────────┘                              ▼              │
│             │ creates K8s Secret              ┌──────────────────┐    │
│             ▼                                 │ Vault            │    │
│  namespace: task-mservice (etc.)              │ namespace: vault │    │
│  ┌──────────────────────┐                     │ KV v2: secret/  │    │
│  │ Pod (task-mservice)  │◄── envFrom Secret   │ standalone+PVC │    │
│  │ MYSQL_DSN            │                     └──────────────────┘    │
│  └──────────────────────┘                                              │
└─────────────────────────────────────────────────────────────────────────┘
```

| Component | Namespace | Purpose |
| --------- | --------- | ------- |
| HashiCorp Vault | `vault` | Source of truth for secrets (KV v2) |
| External Secrets Operator | `external-secrets` | Sync Vault → Kubernetes Secrets |
| ClusterSecretStore `vault-backend` | cluster-scoped | Vault connection for all GitOps repos |
| Microservices | per-service ns | Consume K8s Secrets (not Vault directly) |

Future services (`task-mservice`, `campaign-api`, `reward-service`, `user-service`, `payment-service`) receive secrets via **ExternalSecret** resources managed by ArgoCD.

## How Vault works

1. **Install** — Ansible deploys the [HashiCorp Vault Helm chart](https://helm.releases.hashicorp.com) in **standalone** mode with a **10Gi PVC** (file storage).
2. **Initialize** — `vault operator init` generates unseal key(s) and a root token (stored locally under `vault-keys/<env>/`, gitignored).
3. **Unseal** — Vault starts sealed after restart; unseal with `vault-unseal.sh` (dev uses 1-of-1; production should use Shamir 5/3 + auto-unseal).
4. **Bootstrap** — Enable KV v2 at `secret/`, Kubernetes auth, policy, and role `campaign-center`.
5. **Store secrets** — `vault kv put secret/campaign-center/<env>/<service> KEY=value`.
6. **UI** — `kubectl port-forward -n vault svc/vault 8200:8200` → http://localhost:8200 (ClusterIP only; no ingress by default).

Vault API (in-cluster): `http://vault.vault.svc.cluster.local:8200`

## How External Secrets works

1. **ClusterSecretStore** `vault-backend` points at Vault with **Kubernetes auth** and role `campaign-center`.
2. ESO uses ServiceAccount `external-secrets-vault` (namespace `external-secrets`) to obtain a Vault token.
3. An **ExternalSecret** in a microservice namespace declares which Vault path/properties to sync.
4. ESO creates/updates a native **Kubernetes Secret** (e.g. `task-mservice-secrets`).
5. The Deployment mounts or references that Secret (`envFrom.secretRef` or `valueFrom.secretKeyRef`).

Example ExternalSecret: [`ansible/roles/external-secrets/files/example-externalsecret.yaml`](ansible/roles/external-secrets/files/example-externalsecret.yaml)

## Secret path convention

KV v2 mount: `secret/`  
Logical paths:

```text
secret/data/campaign-center/dev/task-mservice
secret/data/campaign-center/dev/campaign-api
secret/data/campaign-center/staging/task-mservice
secret/data/campaign-center/prod/task-mservice
```

CLI uses the path **without** `/data/`:

```text
secret/campaign-center/dev/task-mservice
```

Policy `campaign-center` grants **read** on `secret/data/campaign-center/*`.

## Install (infrastructure repo)

Prerequisites: k3s running, `kubeconfigs/<env>.yaml` present.

```bash
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml

# 1. Helm install Vault + External Secrets + ClusterSecretStore
./ansible/scripts/install-vault.sh dev

# 2. One-time cluster bootstrap (order matters)
./ansible/scripts/vault-init.sh dev
./ansible/scripts/vault-unseal.sh dev
./ansible/scripts/vault-bootstrap.sh dev
```

After bootstrap, verify:

```bash
kubectl get pods -n vault
kubectl get pods -n external-secrets
kubectl get clustersecretstore vault-backend
kubectl describe clustersecretstore vault-backend
```

ClusterSecretStore should report **Ready=True** once Kubernetes auth is configured.

## How applications retrieve `MYSQL_DSN`

### 1. Store in Vault (platform admin)

Do **not** commit credentials to git. Provide the DSN at runtime:

```bash
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=$(cat vault-keys/dev/root.token)

kubectl port-forward -n vault svc/vault 8200:8200 &
sleep 2

# Prompt for DSN (not echoed)
read -rs MYSQL_DSN
vault kv put secret/campaign-center/dev/task-mservice MYSQL_DSN="${MYSQL_DSN}"
unset MYSQL_DSN
```

Verify:

```bash
vault kv get -field=MYSQL_DSN secret/campaign-center/dev/task-mservice
# or metadata only:
vault kv metadata get secret/campaign-center/dev/task-mservice
```

### 2. Sync to Kubernetes (GitOps repo)

ArgoCD applies an ExternalSecret in namespace `task-mservice`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: task-mservice-secrets
  namespace: task-mservice
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: task-mservice-secrets
  data:
    - secretKey: MYSQL_DSN
      remoteRef:
        key: campaign-center/dev/task-mservice
        property: MYSQL_DSN
```

### 3. Consume in Deployment (GitOps repo)

```yaml
env:
  - name: MYSQL_DSN
    valueFrom:
      secretKeyRef:
        name: task-mservice-secrets
        key: MYSQL_DSN
```

The application never talks to Vault directly — only to the synced Kubernetes Secret.

## How to add a new secret

1. Choose path: `secret/campaign-center/<env>/<service>`.
2. Write secret (interactive or from env var, never hardcode in repo):

   ```bash
   read -rs NEW_API_KEY
   vault kv put secret/campaign-center/dev/campaign-api API_KEY="${NEW_API_KEY}"
   unset NEW_API_KEY
   ```

3. Add a `data` entry to the service's ExternalSecret in the GitOps repo.
4. ArgoCD syncs; ESO refreshes within `refreshInterval` (or force reconcile):

   ```bash
   kubectl annotate externalsecret task-mservice-secrets \
     -n task-mservice force-sync=$(date +%s) --overwrite
   ```

## How to rotate a secret

1. Write new value to Vault (same path, new version — KV v2 keeps versions):

   ```bash
   read -rs MYSQL_DSN
   vault kv put secret/campaign-center/dev/task-mservice MYSQL_DSN="${MYSQL_DSN}"
   unset MYSQL_DSN
   ```

2. ESO picks up the latest version on next refresh, or force sync (see above).
3. Restart pods if they don't reload secrets automatically:

   ```bash
   kubectl rollout restart deployment/task-mservice -n task-mservice
   ```

4. Confirm version in Vault:

   ```bash
   vault kv metadata get secret/campaign-center/dev/task-mservice
   ```

## How to verify secret synchronization

```bash
# ClusterSecretStore health
kubectl get clustersecretstore vault-backend
kubectl describe clustersecretstore vault-backend

# ExternalSecret status (in app namespace)
kubectl get externalsecret -n task-mservice
kubectl describe externalsecret task-mservice-secrets -n task-mservice

# Resulting Kubernetes Secret (keys only — do not log values in shared channels)
kubectl get secret task-mservice-secrets -n task-mservice -o jsonpath='{.data}' | jq 'keys'

# ESO controller logs
kubectl logs -n external-secrets deployment/external-secrets --tail=50
```

Expected ExternalSecret status: `SecretSynced` / `Ready=True`.

## Ansible variables

| Role | Key defaults | File |
| ---- | ------------ | ---- |
| Vault | `vault_namespace=vault`, `vault_storage_size=10Gi`, standalone | `ansible/roles/vault/defaults/main.yml` |
| ESO | `external_secrets_namespace=external-secrets`, `vault-backend` | `ansible/roles/external-secrets/defaults/main.yml` |

Disable components: `vault_enabled: false` or `external_secrets_enabled: false`.

## Kubernetes auth details

| Item | Value |
| ---- | ----- |
| Auth mount | `kubernetes` |
| Role | `campaign-center` |
| Policy | `campaign-center` (read `secret/data/campaign-center/*`) |
| ESO ServiceAccount | `external-secrets-vault` @ `external-secrets` |
| Token reviewer SA | `vault-auth-reviewer` @ `vault` (system:auth-delegator) |

To allow a microservice ServiceAccount direct Vault access (uncommon with ESO), extend the role:

```bash
vault write auth/kubernetes/role/campaign-center \
  bound_service_account_names=external-secrets-vault,task-mservice \
  bound_service_account_namespaces=external-secrets,task-mservice \
  policies=campaign-center ttl=24h
```

## Vault UI via Traefik Ingress (optional)

Vault service stays **ClusterIP**. UI exposure uses a standard **Kubernetes Ingress** (`ingressClassName: traefik`) with **HTTPS** and **access control** — plain HTTP exposure is blocked by Ansible assertions.

**Default:** `vault_ingress_enabled: false` (port-forward only).

### Enable ingress

**Option A — cert-manager + BasicAuth**

```bash
# Install cert-manager and create a ClusterIssuer first (if not present)
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
VAULT_INGRESS_HOST=vault.dev.example.com \
VAULT_INGRESS_BASIC_AUTH_PASSWORD='your-strong-password' \
VAULT_INGRESS_CLUSTER_ISSUER=letsencrypt-prod \
./ansible/scripts/configure-vault-ingress.sh dev
```

**Option B — manual TLS secret (no cert-manager)**

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/vault-tls.key -out /tmp/vault-tls.crt \
  -subj "/CN=vault.dev.example.com"

kubectl create secret tls vault-ingress-tls -n vault \
  --cert=/tmp/vault-tls.crt --key=/tmp/vault-tls.key

VAULT_INGRESS_BASIC_AUTH_PASSWORD='your-strong-password' \
./ansible/scripts/configure-vault-ingress.sh dev
```

**Option C — IP allowlist (or combine with BasicAuth)**

```bash
VAULT_INGRESS_AUTH_MODE=ipallowlist \
VAULT_INGRESS_IP_ALLOWLIST='203.0.113.10/32,10.0.0.0/8' \
VAULT_INGRESS_CLUSTER_ISSUER=letsencrypt-prod \
./ansible/scripts/configure-vault-ingress.sh dev
```

### What gets created (namespace `vault`)

| Resource | Purpose |
| -------- | ------- |
| `Ingress` `vault` | Host `vault.dev.example.com` → service `vault:8200` |
| `Middleware` `vault-basicauth` | Traefik BasicAuth (optional) |
| `Middleware` `vault-ipallowlist` | Traefik IP allowlist (optional) |
| `Secret` `vault-basicauth` | htpasswd users for BasicAuth |
| TLS | cert-manager Certificate or `vault-ingress-tls` secret |

Open: `https://vault.dev.example.com/ui`

### Ingress variables (`ansible/roles/vault/defaults/main.yml`)

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `vault_ingress_enabled` | `false` | Create Ingress + middlewares |
| `vault_ingress_host` | `vault.dev.example.com` | Host header |
| `vault_ingress_class_name` | `traefik` | IngressClass |
| `vault_ingress_auth_mode` | `basicauth` | `basicauth`, `ipallowlist`, or `both` |
| `vault_ingress_cluster_issuer` | `""` | cert-manager ClusterIssuer |
| `vault_ingress_tls_secret_name` | `vault-ingress-tls` | TLS secret when not using cert-manager |

Helm chart `server.ingress.enabled` remains **false** — Ingress is managed by Ansible templates, not the Vault chart.

## Dev vs production evolution

| Concern | Dev (current) | Production target |
| ------- | ------------- | ----------------- |
| Vault mode | Standalone, 1 replica | HA + Raft or external storage |
| Unseal | Manual, 1/1 Shamir | 5/3 Shamir + auto-unseal (KMS) |
| TLS | Disabled on listener | Traefik Ingress + TLS + BasicAuth/IP allowlist |
| Ingress | Disabled by default | `configure-vault-ingress.sh` (opt-in) |
| Root token | Local file | Revoke after bootstrap; use break-glass |
| Backups | PVC snapshot | Scheduled snapshots + DR runbook |

## Troubleshooting

| Issue | Action |
| ----- | ------ |
| Vault pod Running but API sealed | `./ansible/scripts/vault-unseal.sh dev` |
| ClusterSecretStore not Ready | Run `vault-bootstrap.sh`; check `kubectl logs -n external-secrets deployment/external-secrets` |
| ExternalSecret `SecretSyncedError` | Verify path exists: `vault kv get secret/campaign-center/dev/task-mservice` |
| Permission denied | Re-run bootstrap; confirm policy and role bindings |
| Re-init needed | **Destructive** — delete PVC `data-vault-0`, reinstall, init again |

## Related files

```text
ansible/roles/vault/                    # Vault Helm + auth reviewer SA
ansible/roles/external-secrets/         # ESO Helm + ClusterSecretStore
ansible/scripts/install-vault.sh
ansible/scripts/vault-init.sh
ansible/scripts/vault-unseal.sh
ansible/scripts/vault-bootstrap.sh
vault-keys/<env>/                       # gitignored init material
```
