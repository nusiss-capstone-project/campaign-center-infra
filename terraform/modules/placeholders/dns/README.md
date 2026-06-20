# DNS (Alibaba Cloud DNS) — placeholder

Future use: public DNS records pointing to the K3s ingress load balancer or EIP.

## Planned integration

- `A`/`AAAA` records for API and application hostnames
- Optional wildcard records for dev/staging environments
- Coordinate with the SLB/EIP module outputs

## References

- [Alibaba Cloud DNS Terraform docs](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/alidns_record)
