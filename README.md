# campaign-center-infra

Terraform and Ansible automation for deploying a **K3s-based microservice platform** on Alibaba Cloud.

This repository manages **cloud infrastructure and K3s cluster bootstrap only**. Application Kubernetes manifests and GitOps workflows live in a separate repository.

## Scope


| In scope                                      | Out of scope                    |
| --------------------------------------------- | ------------------------------- |
| VPC, VSwitch, Security Groups                 | Business microservice manifests |
| ECS nodes for K3s (master + optional workers) | Rancher, Fleet, ArgoCD          |
| EIP for master (or future SLB)                | Application deployment          |
| Ansible K3s install / verify / reset          | Platform add-ons beyond K3s     |


## Repository layout

```text
.
├── terraform/
│   ├── environments/dev/     # Per-environment stacks (dev, pre, prod)
│   └── modules/              # Reusable Terraform modules
├── ansible/
│   ├── inventories/<env>/    # Generated inventory (do not edit)
│   ├── playbooks/            # install, verify, reset
│   ├── roles/                # common, k3s-server, k3s-agent
│   └── scripts/              # Wrapper scripts
├── kubeconfigs/              # Fetched kubeconfig files (gitignored)
├── scripts/                  # Terraform fmt / validate helpers
└── docs/
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/index.html) >= 2.14
- `jq` (for inventory generation)
- Alibaba Cloud account with RAM credentials
- ECS key pair in the target region
- SSH private key matching the key pair

## Credentials

```bash
export ALICLOUD_ACCESS_KEY="your-access-key"
export ALICLOUD_SECRET_KEY="your-secret-key"
```

## Quick start (dev)

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
brew install ansible jq
```

Linux:

```bash
sudo apt install ansible jq    # Debian/Ubuntu
sudo dnf install ansible jq    # RHEL/Alibaba Cloud Linux
```

### 3. Configure SSH

Point to the private key that matches your ECS key pair:

```bash
export SSH_PRIVATE_KEY=~/.ssh/campaign-center-key
chmod 600 "$SSH_PRIVATE_KEY"
```

Optional — pin K3s version (default `v1.30.5+k3s1`):

```bash
export K3S_VERSION=v1.35.5+k3s1
```

### 4. Install and verify K3s

From the repository root:

```bash
./ansible/scripts/install-k3s.sh dev
```

This will:

1. Read Terraform outputs from `terraform/environments/dev`
2. Generate `ansible/inventories/dev/hosts.yml`
3. Run `install-k3s.yml` then `verify-k3s.yml`
4. Fetch kubeconfig to `kubeconfigs/dev.yaml`

Use the cluster:

```bash
export KUBECONFIG=$(pwd)/kubeconfigs/dev.yaml
kubectl get nodes
```

### 5. Manual steps (optional)

Generate inventory only:

```bash
./ansible/scripts/generate-inventory.sh dev
```

Verify an existing cluster:

```bash
./ansible/scripts/verify-k3s.sh dev
```

Reset (destructive):

```bash
CONFIRM_RESET=true ./ansible/scripts/reset-k3s.sh dev
```

## Terraform outputs used by Ansible

The inventory script reads `terraform output -json` and accepts these names (plural preferred, singular normalized to arrays):


| Purpose            | Accepted output names                          |
| ------------------ | ---------------------------------------------- |
| Master public IPs  | `master_public_ips`, `k3s_master_public_ip(s)` |
| Master private IPs | `master_private_ips`, `k3s_master_private_ips` |
| Worker public IPs  | `worker_public_ips` (optional)                 |
| Worker private IPs | `worker_private_ips`, `k3s_worker_private_ips` |


Fails clearly if no master private IP or no master public IP is found.

## OSS remote state

```bash
cp terraform/backend.tf.example terraform/environments/dev/backend.tf
cd terraform/environments/dev
terraform init -reconfigure
```

## Key Terraform variables


| Variable                                  | Description                                                 |
| ----------------------------------------- | ----------------------------------------------------------- |
| `region`                                  | Alibaba Cloud region                                        |
| `zones`                                   | Availability zones (multi-AZ)                               |
| `vswitch_cidrs`                           | VSwitch CIDR per zone                                       |
| `master_count` / `worker_count`           | K3s node counts                                             |
| `create_eip`                              | Public IP for master SSH (required for Ansible from laptop) |
| `allowed_ssh_cidr` / `allowed_admin_cidr` | Security group CIDRs (dev defaults open)                    |


## Ansible behaviour

- **Server nodes**: official K3s install script, `--node-ip` / `--advertise-address` use private IP, `--tls-san` includes public + private IP, `--disable servicelb` (SLB later), Traefik left enabled.
- **Agent nodes**: join via first master's private IP `:6443`; skipped when no workers in inventory.
- **Idempotent**: skips install when `/usr/local/bin/k3s` exists and systemd service is active.
- **HA-ready**: multiple masters use `--cluster-init` on the first server and join others serially.

## Troubleshooting


| Issue                    | Check                                                                                  |
| ------------------------ | -------------------------------------------------------------------------------------- |
| SSH timeout              | Security group allows SSH from your IP; `create_eip = true`; correct `SSH_PRIVATE_KEY` |
| No master public IP      | `terraform output master_public_ips`; enable EIP and re-apply                          |
| Port 6443 blocked        | Open `allowed_admin_cidr` in tfvars or use kubeconfig via SSH tunnel                   |
| Worker not joining       | Worker needs network path to master private IP; agents use private IP for `K3S_URL`    |
| Terraform output missing | Run from `terraform/environments/<env>`; check output names in table above             |
| K3s install fails        | SSH to master, check `journalctl -u k3s`; ensure outbound internet for get.k3s.io      |


## Documentation

- [Architecture](docs/architecture.md)
- [Bootstrap K3s (manual reference)](docs/bootstrap-k3s.md)
- [Operations](docs/operations.md)

## License

Internal infrastructure code for the campaign-center platform.