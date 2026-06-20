# Production environment

This directory is reserved for the **prod** environment.

## Status

Not yet implemented. Production should include:

- Multi-master K3s behind SLB (`eip_attachment_mode = "slb"`)
- Stricter security group CIDRs (no `0.0.0.0/0` for admin ports)
- Larger or dedicated instance types per node role
- Remote state in a dedicated OSS bucket with least-privilege RAM policies
- Optional RDS, Redis, OSS, and DNS modules from `modules/placeholders/`

## HA notes

1. Provision multiple master nodes via `master_count`.
2. Enable the SLB placeholder module and attach the EIP to the load balancer.
3. Point DNS to the SLB/EIP for the Kubernetes API endpoint.
4. Bootstrap K3s with embedded etcd or external datastore per your HA design.

Kubernetes application deployment is intentionally out of scope for this repository and will be managed via GitOps.
