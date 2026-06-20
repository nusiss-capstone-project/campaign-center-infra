# SLB (Server Load Balancer) — placeholder

Future use: terminate HTTPS/TCP for the K3s API and ingress controllers in multi-master HA production.

## Planned integration

- Create an internet-facing SLB in the VPC
- Add listeners for TCP 6443 (K3s API) and HTTP/HTTPS as needed
- Set `eip_attachment_mode = "slb"` in the EIP module
- Register master nodes as backend servers

## References

- [Alibaba Cloud SLB Terraform docs](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/slb_load_balancer)
