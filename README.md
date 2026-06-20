# campaign-center-infra

Terraform and Ansible automation for deploying a **K3s-based microservice platform** on Alibaba Cloud.

This repository manages **cloud infrastructure and K3s cluster bootstrap only**. Application Kubernetes manifests and GitOps workflows live in a separate repository.

## Scope


| In scope                                      | Out of scope                    |
| --------------------------------------------- | ------------------------------- |
| VPC, VSwitch, Security Groups                 | Business microservice manifests |
| ECS nodes for K3s (master + optional workers) | Fleet, ArgoCD, app deployment   |
| EIP for master (or future SLB)                |                                 |
| Ansible K3s install / verify / reset          |                                 |
| Headlamp UI + Traefik ingress (dev)           | Rancher (removed — too heavy)   |
| Kafka (dev, in-cluster)                       |                                 |
| Kafka UI (dev, via Traefik)                   |                                 |


## Why Headlamp instead of Rancher?

Rancher was removed from the dev environment. On a single-node K3s cluster it caused:

- High memory/CPU usage and API slowness
- cert-manager / webhook timeouts
- Operational overhead disproportionate to a dev/demo cluster

**Headlamp** is a lightweight, Kubernetes-native web UI. It uses standard RBAC and service account tokens for login — no separate control plane. Traefik remains the unified HTTP entrypoint for Headlamp and future tools (Grafana, AKHQ, RedisInsight, CloudBeaver).

## Repository layout

```text
.
├── terraform/
│   ├── environments/dev/     # Per-environment stacks (dev, pre, prod)
│   └── modules/              # Reusable Terraform modules
├── ansible/
│   ├── inventories/<env>/    # Generated inventory (do not edit)
│   ├── playbooks/            # k3s, traefik, headlamp, kafka, kafka-ui, site.yml
│   ├── roles/
│   │   ├── kafka/            # Apache Kafka (KRaft, templated manifests)
│   │   ├── kafka-ui/         # Provectus Kafka UI + Traefik route
│   │   ├── headlamp/         # K8s UI + Traefik route
│   │   ├── traefik/          # K3s Traefik hostPort exposure
│   │   ├── redis/            # placeholder
│   │   ├── mysql/            # placeholder
│   │   ├── akhq/             # placeholder
│   │   └── monitoring/       # placeholder (Grafana, etc.)
│   └── scripts/              # Wrapper scripts
├── .github/workflows/        # CI (Checkov security scan)
├── kubeconfigs/              # Fetched kubeconfig files (gitignored)
├── scripts/                  # Terraform fmt / validate helpers
└── docs/
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html) >= 2.14
- `jq` (for inventory generation)
- `kubectl` and `helm` (for Headlamp install)
- Ansible collection `kubernetes.core` (installed automatically by install scripts)
- Alibaba Cloud account with RAM credentials
- ECS key pair in the target region
- SSH private key matching the key pair

## Credentials

```bash
export ALICLOUD_ACCESS_KEY="your-access-key"
export ALICLOUD_SECRET_KEY="your-secret-key"
```

## Quick start (dev)

### Platform install order

```text
K3s  →  Traefik (hostPort)  →  Headlamp (+ IngressRoute)  →  Kafka (in-cluster)  →  Kafka UI (+ IngressRoute)
```

Or install the full platform stack (after K3s):

```bash
./ansible/scripts/install-platform.sh dev
```

### 1. Provision infrastructure with Terraform

```bash
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
# Edit region, zones, image_id, key_pair_name, create_eip, etc.

cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

Ensure `create_eip = true` unless you will reach nodes another way — Ansible needs at least one **master public IP** for SSH.

### 2. Install Ansible (local)

macOS:

```bash
brew install ansible jq kubectl helm
```

Linux:

```bash
sudo apt install ansible jq    # Debian/Ubuntu
sudo dnf install ansible jq    # RHEL/Alibaba Cloud Linux
# Install kubectl and helm from vendor docs
```

### 3. Configure SSH

```bash
export SSH_PRIVATE_KEY=~/.ssh/campaign-center-key.pem
chmod 600 "$SSH_PRIVATE_KEY"
```

Optional — pin K3s version:

```bash
export K3S_VERSION=v1.35.5+k3s1
```

### 4. Install and verify K3s

```bash
./ansible/scripts/install-k3s.sh dev
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
kubectl get nodes
```

### 5. Configure Traefik exposure (dev hostPort)

Configures **K3s built-in Traefik** only — does not install a second instance.

```bash
./ansible/scripts/install-traefik.sh dev
```

- Applies `HelmChartConfig/traefik` with **hostPort 80/443** (no random NodePorts)
- Service type `ClusterIP`
- Application routes (Headlamp, etc.) are added by each app role

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `traefik_exposure_mode` | `hostport` | Dev only; `loadbalancer` reserved for prod |
| `traefik_http_port` | `80` | Host HTTP port |
| `traefik_https_port` | `443` | Host HTTPS port |

### 6. Install Headlamp

Installs Headlamp via official Helm chart and exposes it through Traefik. Also **removes legacy Rancher** (and cert-manager, if present) from the cluster.

```bash
./ansible/scripts/install-headlamp.sh dev
```

**Access Headlamp**

- URL: `http://headlamp.<master_public_ip>.sslip.io` (override with `HEADLAMP_HOST`)
- Login: open UI → **Authenticate** → paste a service account token:

```bash
kubectl -n headlamp create token headlamp-dev
```

The dev ServiceAccount is bound to `cluster-admin` for simplicity. Restrict RBAC in non-dev environments.

**Headlamp variables** (`ansible/roles/headlamp/defaults/main.yml`)

| Variable | Description |
| -------- | ----------- |
| `headlamp_host` | Hostname for Traefik route (default from inventory + sslip.io) |
| `headlamp_cleanup_rancher` | Uninstall Rancher Helm release and routes (default `true`) |
| `headlamp_cleanup_cert_manager` | Uninstall cert-manager if only used by Rancher (default `true`) |

**Validation**

```bash
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl get ingressroute -A
kubectl describe ingressroute headlamp -n headlamp
ss -lntp | grep -E ':80|:443'   # on K3s master
curl -v -H 'Host: headlamp.<master_public_ip>.sslip.io' http://<master_public_ip>/
```

### 7. Install Kafka (optional, dev/demo)

Lightweight **Apache Kafka** single broker (KRaft, no ZooKeeper). Deployed via templated Kubernetes manifests — **not** exposed via Traefik, NodePort, or public security group ports.

```bash
./ansible/scripts/install-kafka.sh dev
```

**In-cluster bootstrap**

```text
kafka.messaging.svc.cluster.local:9092
```

Use from pods in the same cluster (e.g. future microservices). Use Kafka UI (below) for browser-based topic inspection.

**Local development access** (from your laptop)

```bash
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml

# Port-forward (ClusterIP → localhost)
kubectl port-forward -n messaging svc/kafka 9092:9092

# Recommended for CLI smoke tests — exec into the broker pod
kubectl exec -it -n messaging kafka-0 -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list
```

**Kafka variables** (`ansible/roles/kafka/defaults/main.yml`)

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `kafka_enabled` | `true` | Skip install when `false` |
| `kafka_namespace` | `messaging` | Namespace |
| `kafka_image` | `apache/kafka:4.0.0` | Official Apache Kafka image |
| `kafka_storage_size` | `2Gi` | PVC size per broker |
| `kafka_memory_request` / `limit` | `512Mi` / `768Mi` | Memory |
| `kafka_cpu_request` / `limit` | `100m` / `500m` | CPU |

**Validation**

```bash
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
kubectl get pods -n messaging
kubectl get svc -n messaging
kubectl logs -n messaging statefulset/kafka --tail=30
kubectl exec -n messaging kafka-0 -- /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list
```

### 8. Install Kafka UI (optional, dev/demo)

Lightweight **Provectus Kafka UI** in namespace `messaging`, connected to the existing Kafka broker and exposed via Traefik at `kafka.<base-domain>` (default: `kafka.<master_public_ip>.sslip.io`).

```bash
./ansible/scripts/install-kafka-ui.sh dev
```

Requires Kafka (`install-kafka.sh`) and Traefik (`install-traefik.sh`) first.

**URL**

```text
http://kafka.<master_public_ip>.sslip.io
```

Override hostname: `KAFKA_UI_HOST=kafka.example.com ./ansible/scripts/install-kafka-ui.sh dev`

**Kafka UI variables** (`ansible/roles/kafka-ui/defaults/main.yml`)

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `kafka_ui_enabled` | `true` | Skip install when `false` |
| `kafka_ui_namespace` | `messaging` | Namespace (shared with Kafka broker) |
| `kafka_ui_image` | `provectuslabs/kafka-ui:v0.7.2` | Provectus Kafka UI image |
| `kafka_ui_bootstrap_servers` | `kafka.messaging.svc.cluster.local:9092` | Broker bootstrap |
| `kafka_ui_memory_request` / `limit` | `128Mi` / `256Mi` | Memory |
| `kafka_ui_cpu_request` / `limit` | `50m` / `200m` | CPU |

**Validation**

```bash
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
kubectl get pods -n messaging -l app.kubernetes.io/name=kafka-ui
kubectl describe ingressroute kafka-ui -n messaging
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'Host: kafka.<master_public_ip>.sslip.io' http://<master_public_ip>/
```

**Full dev stack** (`playbooks/site.yml`):

```bash
./ansible/scripts/install-platform.sh dev
# or: ansible-playbook -i ansible/inventories/dev/hosts.yml ansible/playbooks/site.yml
```

### 9. Manual steps (optional)

```bash
./ansible/scripts/generate-inventory.sh dev
./ansible/scripts/verify-k3s.sh dev
CONFIRM_RESET=true ./ansible/scripts/reset-k3s.sh dev
```

## Extending Traefik routing (future tools)

Each management tool gets its own Ansible role following the Headlamp pattern:

1. Helm install into a dedicated namespace
2. `IngressRoute` template with `Host(\`tool.<eip>.sslip.io\`)` 
3. Traefik `web` entrypoint (HTTP dev) or `websecure` + cert-manager later

Examples to add the same way: **Grafana**, **RedisInsight**, **CloudBeaver**. Kafka UI uses the same IngressRoute pattern (`roles/kafka-ui`).

**Data / messaging components** (Redis, MySQL, Kafka) follow: Ansible role → templated K8s manifests → namespace → validation. Kafka UI adds Traefik routing on top.

Traefik exposure (`install-traefik.sh`) stays separate from app routing (`install-<app>.sh`). The Kafka **broker** stays cluster-internal; only Kafka **UI** is routed through Traefik.

## Terraform outputs used by Ansible

| Purpose | Primary keys | Fallback keys |
|---------|--------------|---------------|
| Master public IPs | `k3s_master_public_ip`, `k3s_master_public_ips` | `master_public_ip(s)`, `ssh_command` |
| Master private IPs | `k3s_master_private_ips` | `master_private_ip(s)` |
| Worker public IPs | `k3s_worker_public_ip(s)` | `worker_public_ip(s)` |
| Worker private IPs | `k3s_worker_private_ips` | `worker_private_ip(s)` |

## Key Terraform variables

| Variable | Description |
| -------- | ----------- |
| `region` | Alibaba Cloud region |
| `zones` | Availability zones (multi-AZ) |
| `image_id` | ECS image ID (Ubuntu 22.04 20G) |
| `master_count` / `worker_count` | K3s node counts |
| `create_eip` | Public IP for master SSH |
| `allowed_ssh_cidr` / `allowed_admin_cidr` | Security group CIDRs |

## Ansible behaviour

- **K3s server**: private IP for `--node-ip`, TLS SANs for public + private IP, `--disable servicelb`, Traefik enabled.
- **Registry mirrors**: `/etc/rancher/k3s/registries.yaml` for faster `docker.io` pulls in CN.
- **Traefik (dev)**: `HelmChartConfig` hostPort 80/443; no second Traefik install.
- **Headlamp**: official Helm chart, `IngressRoute` via Traefik, token-based K8s auth.
- **Kafka (dev)**: Apache official image, KRaft single broker, namespace `messaging`, cluster-internal `ClusterIP` only (templated manifests).
- **Kafka UI (dev)**: Provectus Kafka UI, namespace `messaging`, Traefik IngressRoute at `kafka.<base-domain>`.
- **Idempotent**: `kubernetes.core.k8s` apply; safe to re-run install scripts.

## Troubleshooting

| Issue | Check |
| ----- | ----- |
| SSH timeout | Security group, EIP, `SSH_PRIVATE_KEY` |
| Headlamp 404 | `install-traefik.sh` then `install-headlamp.sh`; `kubectl describe ingressroute headlamp -n headlamp` |
| Traefik not on :80/:443 | `kubectl get helmchartconfig traefik -n kube-system -o yaml`; `ss -lntp` on master |
| Headlamp login fails | `kubectl -n headlamp create token headlamp-dev`; check RBAC |
| Slow API after Rancher | Re-run `install-headlamp.sh` to uninstall Rancher/cert-manager leftovers |
| ImagePullBackOff | Registry mirrors in `/etc/rancher/k3s/registries.yaml`; re-run `install-k3s.sh` |
| Kafka pod pending / CrashLoop | `kubectl describe pod -n messaging kafka-0`; check node memory and `apache/kafka` image pull |
| Kafka not reachable from app | Use in-cluster DNS `kafka.messaging.svc.cluster.local:9092`, not public IP |
| Local laptop cannot connect to Kafka | Use `kubectl port-forward` or exec CLI inside `kafka-0`; advertised listener is cluster DNS |
| Kafka UI 404 / unreachable | Run `install-traefik.sh` then `install-kafka-ui.sh`; `kubectl describe ingressroute kafka-ui -n messaging` |
| Kafka UI shows no brokers | Ensure Kafka broker is Running; check `kafka_ui_bootstrap_servers` in role defaults |

## CI / security scanning

[Checkov](https://www.checkov.io/) runs on pull requests and pushes to `main`/`master` when `terraform/` or `ansible/` changes.

| Scan target | Path |
| ----------- | ---- |
| Terraform (Alibaba Cloud) | `terraform/` |
| Ansible playbooks / roles | `ansible/` |
| GitHub Actions | `.github/workflows/` |

Configuration: [`.checkov.yaml`](.checkov.yaml). Jinja2 templates (`*.j2`) are skipped (rendered at deploy time). To suppress a known dev finding, add its check ID to `skip-check` in `.checkov.yaml` with a comment explaining why.

**Run locally**

```bash
pip install checkov
checkov -d . --config-file .checkov.yaml
```

SARIF results are uploaded to GitHub **Code scanning** when available (requires GitHub Advanced Security on private repos).

## Documentation

- [Architecture](docs/architecture.md)
- [Bootstrap K3s (manual reference)](docs/bootstrap-k3s.md)
- [Operations](docs/operations.md)

## License

Internal infrastructure code for the campaign-center platform.
