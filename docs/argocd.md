# Argo CD — GitOps bootstrap

Argo CD syncs Kubernetes resources from Git to the cluster. This **IaC repository** installs Argo CD and bootstraps the **root Application** via the Ansible role [`ansible/roles/argocd/`](../ansible/roles/argocd/). Application manifests live in **[campaign-gitops](https://github.com/nusiss-capstone-project/campaign-gitops)**.

## Repository responsibilities

| IaC repo (campaign-center-infra) | GitOps repo (campaign-gitops) |
| -------------------------------- | ----------------------------- |
| ECS, VPC, security groups | Application Deployments / Services |
| k3s cluster bootstrap | IngressRoutes / Ingress per app |
| Traefik, Headlamp, Kafka, Vault | Helm charts & `values.yaml` |
| External Secrets Operator | Image tags & app configuration |
| Argo CD Helm install | Child Argo CD Applications |
| Root Application `campaign-gitops-root` | task-mservice, campaign-api, … |

Do **not** put task-mservice Deployment/Service/Ingress or app Helm values in this repo.

## What Argo CD does

1. Watches Git for manifest changes.
2. Compares desired (Git) vs live (cluster) state.
3. Syncs automatically when configured.
4. Exposes UI/CLI for visibility.

## App-of-apps pattern

```text
ansible/roles/argocd/templates/campaign-gitops-root.yaml.j2
  └── Application: campaign-gitops-root
        └── monitors campaign-gitops @ dev / argocd/applications/
              ├── task-mservice.yaml
              ├── campaign-api.yaml
              └── ...
```

The role applies the root Application automatically after Argo CD is ready.

## Install

Prerequisites: k3s, Traefik, kubeconfig.

```bash
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml

# Default host: argocd.<master_public_ip>.sslip.io
./ansible/scripts/install-argocd.sh dev

# Or full platform stack (includes Argo CD):
./ansible/scripts/install-platform.sh dev
```

Override hostname:

```bash
export ARGOCD_HOST=argocd.8.219.134.169.sslip.io
./ansible/scripts/install-argocd.sh dev
```

Optional cert-manager TLS:

```bash
export ARGOCD_CLUSTER_ISSUER=letsencrypt-prod
./ansible/scripts/install-argocd.sh dev
```

## Access the UI

- URL: `https://argocd.<master_public_ip>.sslip.io` (or `ARGOCD_HOST`)
- User: **admin**
- Password (not stored in Git):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Service remains **ClusterIP**; traffic enters via Traefik Ingress.

## Verify sync

```bash
kubectl get pods -n argocd
kubectl get ingress -n argocd
kubectl get applications -n argocd
kubectl describe application campaign-gitops-root -n argocd
```

## Ansible variables

See [`ansible/roles/argocd/defaults/main.yml`](../ansible/roles/argocd/defaults/main.yml):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `argocd_enabled` | `true` | Skip role when `false` |
| `argocd_host` | from inventory | `argocd.<ip>.sslip.io` |
| `argocd_gitops_repo_url` | campaign-gitops URL | GitOps repository |
| `argocd_gitops_target_revision` | `dev` | Branch/tag |
| `argocd_bootstrap_root_app` | `true` | Apply root Application |

## Change targetRevision

Edit `argocd_gitops_target_revision` in defaults or patch the Application in the template, then re-run `install-argocd.sh`.

## Private GitOps repo (future)

Public repo needs no credentials. For private repos, see template:

[`ansible/roles/argocd/templates/repository-secret.example.yaml.j2`](../ansible/roles/argocd/templates/repository-secret.example.yaml.j2)

Never commit tokens to Git.

## Role layout

```text
ansible/roles/argocd/
├── defaults/main.yml
├── tasks/
│   ├── main.yml       # Helm install + ingress via values
│   ├── bootstrap.yml  # campaign-gitops-root Application
│   └── validate.yml
└── templates/
    ├── values.yaml.j2
    ├── campaign-gitops-root.yaml.j2
    └── repository-secret.example.yaml.j2
```

## Troubleshooting

| Issue | Check |
| ----- | ----- |
| UI 404 | Traefik running; `kubectl get ingress -n argocd` |
| Redirect loop | `server.insecure: "true"` in values template |
| Root app missing | `argocd_bootstrap_root_app`; role bootstrap task logs |
| TLS error | cert-manager or manual `argocd-server-tls` secret |
