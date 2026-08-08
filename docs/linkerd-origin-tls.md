# Cloudflare Origin TLS + Linkerd

Edge HTTPS uses **Cloudflare** (Universal SSL + Full strict) with a **Cloudflare Origin CA** certificate on Traefik. Linkerd provides **in-cluster mTLS** for app namespaces (wired later in GitOps). These are independent certificate systems.

```text
Browser --HTTPS--> Cloudflare --Full strict--> Traefik (Origin CA Secret)
                                              |
                                              +--> Headlamp / other IngressRoutes

Meshed pods (campaign-dev) <--mTLS--> Meshed pods
Meshed pods --plain/opaque--> Kafka (messaging, unmeshed)
Meshed pods --plain---------> Vault (unmeshed)
```

## 1. Cloudflare Origin TLS

### Dashboard

1. SSL/TLS → Overview → **Full (strict)**
2. SSL/TLS → Origin Server → **Create certificate** (e.g. `*.campaignhub.best`, `campaignhub.best`)
3. DNS: `A`/`CNAME` for hosts (e.g. `headlamp.campaignhub.best`) → master EIP, **proxied** (orange cloud)

### Apply secret into the cluster

```bash
mkdir -p ansible/secrets/origin-tls.dev
# save Origin CA PEM as tls.crt and tls.key (gitignored)

./ansible/scripts/configure-origin-tls.sh dev
```

Default secret name: `campaignhub-origin-tls` in namespace `headlamp`.

Optional env:

| Variable | Default | Meaning |
|----------|---------|---------|
| `ORIGIN_TLS_DIR` | `ansible/secrets/origin-tls.<env>` | Cert directory |
| `ORIGIN_TLS_SECRET_NAME` | `campaignhub-origin-tls` | Secret name |
| `ORIGIN_TLS_NAMESPACES` | `headlamp` | Comma-separated namespaces |

### Headlamp HTTPS

```bash
HEADLAMP_HOST=headlamp.campaignhub.best HEADLAMP_TLS=true \
  ./ansible/scripts/install-headlamp.sh dev
```

Requires the origin secret already present in the `headlamp` namespace.

## 2. Linkerd control plane

Install only the control plane in this repo. **Do not** inject platform namespaces.

```bash
./ansible/scripts/install-linkerd.sh dev
```

- Helm charts: `linkerd-edge/linkerd-crds` + `linkerd-edge/linkerd-control-plane` (pinned `2026.8.1`)
- Identity certs: auto-generated under `ansible/secrets/linkerd.<env>/` (gitignored)
- Control-plane pods soft-prefer workers

### GitOps follow-up (out of scope here)

In the campaign-gitops repo, enable injection on app namespaces only:

```bash
kubectl annotate namespace campaign-dev linkerd.io/inject=enabled --overwrite
kubectl annotate namespace campaign-prod linkerd.io/inject=enabled --overwrite
# restart / redeploy workloads so sidecars are injected
```

**Do not inject:** `kube-system`, `linkerd`, `messaging`, `vault`, `cert-manager`, `external-secrets`, `monitoring`, `argocd`, `headlamp`.

Kafka Service (`messaging/kafka`) is annotated with `config.linkerd.io/opaque-ports: "9092"` so meshed services can still reach the unmeshed broker.

## 3. What we are not doing (plan A)

- No Let’s Encrypt / cert-manager ClusterIssuer for `campaignhub.best`
- Existing `install-cert-manager.yml` remains available for optional Vault LE flows only
- `install-platform.sh` does **not** auto-run origin-tls or Linkerd (opt-in scripts)

## Scripts

| Script | Purpose |
|--------|---------|
| `ansible/scripts/configure-origin-tls.sh <env>` | Apply Origin CA TLS Secret |
| `ansible/scripts/install-linkerd.sh <env>` | Install + verify Linkerd |
| `ansible/scripts/install-headlamp.sh <env>` | Headlamp; set `HEADLAMP_TLS=true` for HTTPS |
