#cloud-config
package_update: true
package_upgrade: false

timezone: Asia/Singapore

packages:
  - curl
  - wget
  - vim
  - git
  - htop
  - jq
  - unzip
  - ca-certificates
  - gnupg
  - lsof
  - net-tools

write_files:
  - path: /etc/motd
    permissions: "0644"
    content: |
      campaign-center node (${role})
      Environment: ${environment}
      Managed by Terraform cloud-init.

  - path: /etc/campaign-center-node
    permissions: "0644"
    content: |
      role=${role}
      environment=${environment}
      project=campaign-center

runcmd:
  - echo "Basic node initialization complete."