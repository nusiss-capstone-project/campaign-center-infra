# RDS MySQL — placeholder

Future use: managed relational database for application services (not for K3s etcd in the default design).

## Planned integration

- Deploy ApsaraDB RDS MySQL in the VPC private subnet
- Security group rules allowing access only from worker/mesh CIDRs or specific SGs
- Credentials via RAM + Secrets Manager / external secret store (never in Terraform state as plain text)

## References

- [Alibaba Cloud RDS Terraform docs](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/db_instance)
