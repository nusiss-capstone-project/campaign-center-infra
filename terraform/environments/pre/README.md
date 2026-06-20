# Pre-production environment

This directory is reserved for the **pre** (staging) environment.

## Status

Not yet implemented. Copy `environments/dev/` as a starting point and adjust:

- Instance sizes and counts (consider multiple workers)
- `allowed_ssh_cidr` and `allowed_admin_cidr` to internal networks only
- OSS remote state prefix: `campaign-center-infra/pre`
- EIP attachment mode (`ecs` vs future `slb` for HA)

## Placeholder modules

When promoting to pre/prod, evaluate enabling modules under `modules/placeholders/`:

- SLB for HA K3s API ingress
- RDS MySQL for persistent data stores
- Redis for caching
- OSS for artifacts and backups
- DNS for public service records

Application workloads remain in a separate GitOps repository.
