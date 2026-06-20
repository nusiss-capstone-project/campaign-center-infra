# OSS (Object Storage Service) — placeholder

Future use:

- Terraform remote state bucket (see `backend.tf.example` at repo root)
- Container image registry artifacts, backups, and static assets

## Planned integration

- Dedicated buckets per environment with encryption and versioning
- RAM policies granting least-privilege access from CI/CD and cluster nodes

## References

- [Alibaba Cloud OSS Terraform docs](https://registry.terraform.io/providers/aliyun/alicloud/latest/docs/resources/oss_bucket)
