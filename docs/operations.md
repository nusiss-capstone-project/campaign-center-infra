# Operations

## Common commands

From the repository root:

```bash
./scripts/fmt.sh
./scripts/validate.sh
./scripts/plan-dev.sh
```

From `environments/dev/`:

```bash
terraform init
terraform plan
terraform apply
terraform destroy
```

## Credentials

Export Alibaba Cloud credentials before running Terraform:

```bash
export ALICLOUD_ACCESS_KEY="your-access-key"
export ALICLOUD_SECRET_KEY="your-secret-key"
# Optional STS token:
# export ALICLOUD_SECURITY_TOKEN="your-token"
```

Never commit credentials or `terraform.tfvars` files.

## Remote state (OSS)

1. Create an OSS bucket and optional Tablestore table for locking.
2. Copy `backend.tf.example` to `environments/dev/backend.tf`.
3. Update bucket name, region, and prefix.
4. Run `terraform init -reconfigure` in the environment directory.

## SSH access

After apply:

```bash
ssh -i ~/.ssh/your-key.pem root@<k3s_master_public_ip>
```

- Restrict `allowed_ssh_cidr` to your VPN or bastion CIDR.
- Default user depends on the chosen `image_id` (Alibaba Cloud Linux: `root`; Ubuntu: `ubuntu`).

## System disk tuning

Adjust in `terraform.tfvars`:

| Variable | Example | Notes |
|----------|---------|-------|
| `system_disk_category` | `cloud_essd` | Use `cloud_efficiency` for lower cost |
| `system_disk_size` | `40` | GiB |
| `system_disk_performance_level` | `PL1` | ESSD only: PL0–PL3 |

## Scaling workers

Set `worker_count` in tfvars and re-apply. Bootstrap each new node per `docs/bootstrap-k3s.md`.

## Troubleshooting

| Issue | Check |
|-------|-------|
| Cannot SSH | Security group `allowed_ssh_cidr`, key pair name, EIP association |
| Cannot reach K3s API | `allowed_admin_cidr`, port 6443 rule, K3s installed |
| Plan fails on image | Set a valid regional `image_id` (e.g. Ubuntu 22.04 20G) |
