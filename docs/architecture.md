# Architecture

## Overview

`campaign-center-infra` provisions Alibaba Cloud foundation resources for a K3s-based microservice platform. This repository manages **cloud infrastructure and cluster bootstrap prerequisites only**. Application Kubernetes manifests are deployed separately via GitOps.

## Components

```text
Internet
   |
   v
 [ EIP ] -----> [ ECS: K3s master ] ----.
   |                                      |
   |                              [ VSwitch / VPC ]
   |                                      |
   +--- (future SLB HA)                   +---- [ ECS: K3s workers ]
```

| Layer | Module | Purpose |
|-------|--------|---------|
| Network | `modules/network` | VPC and VSwitch |
| Security | `modules/security-group` | Ingress/egress rules for SSH, HTTP/S, K3s API, intra-SG traffic |
| Compute | `modules/ecs-k3s-node` | ECS instances with configurable system disks and cloud-init |
| Public access | `modules/eip` | Elastic IP for master (dev) or future SLB (prod HA) |

## Multi-region (方案 A)

Each region is a separate environment directory with its own state:

```text
environments/
  dev-ap-southeast-1/
  prod-ap-southeast-1/
  prod-cn-hangzhou/      # DR region
```

## Multi-AZ (same region)

Within one region, specify multiple zones and per-zone VSwitches:

```hcl
zones = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
vswitch_cidrs = {
  "ap-southeast-1a" = "10.10.1.0/24"
  "ap-southeast-1b" = "10.10.2.0/24"
  "ap-southeast-1c" = "10.10.3.0/24"
}
master_count = 3
```

K3s nodes are placed round-robin across zones (master-1 → 1a, master-2 → 1b, …).
For HA API access, use SLB in front of masters (`eip_attachment_mode = "slb"`, module TBD).

## Environments

| Environment | Status | Notes |
|-------------|--------|-------|
| `dev` | Implemented | Single master, EIP attached to ECS |
| `pre` | Placeholder | Copy dev and harden CIDRs |
| `prod` | Placeholder | Multi-master + SLB + managed data services |

## Tagging

All resources receive:

- `project` — from `project_name`
- `environment` — e.g. `dev`
- `managed_by` — `terraform`

## State

Remote state uses the Terraform OSS backend. See `backend.tf.example` and the root `README.md`.

## Out of scope

- K3s installation (placeholder in cloud-init only)
- Headlamp (dev UI), Fleet, ArgoCD
- Business microservice manifests
