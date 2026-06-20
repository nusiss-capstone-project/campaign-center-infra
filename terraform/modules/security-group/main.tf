locals {
  name_prefix = "${var.project_name}-${var.environment}"
  tags = merge(
    var.common_tags,
    {
      project     = var.project_name
      environment = var.environment
      managed_by  = "terraform"
    }
  )
}

resource "alicloud_security_group" "this" {
  security_group_name = "${local.name_prefix}-sg"
  vpc_id              = var.vpc_id
  # Allow all ingress between instances in this security group (K3s node mesh).
  # Aliyun rejects source_security_group_id == security_group_id on explicit rules;
  # use inner_access_policy instead.
  inner_access_policy = "Accept"
  tags                = local.tags
}

resource "alicloud_security_group_rule" "ssh" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "22/22"
  security_group_id = alicloud_security_group.this.id
  cidr_ip           = var.allowed_ssh_cidr
  description       = "SSH from allowed CIDR"
}

resource "alicloud_security_group_rule" "http" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "80/80"
  security_group_id = alicloud_security_group.this.id
  cidr_ip           = "0.0.0.0/0"
  description       = "HTTP"
}

resource "alicloud_security_group_rule" "https" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "443/443"
  security_group_id = alicloud_security_group.this.id
  cidr_ip           = "0.0.0.0/0"
  description       = "HTTPS"
}

resource "alicloud_security_group_rule" "k3s_api" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "6443/6443"
  security_group_id = alicloud_security_group.this.id
  cidr_ip           = var.allowed_admin_cidr
  description       = "K3s API from allowed admin CIDR"
}

resource "alicloud_security_group_rule" "egress_all" {
  type              = "egress"
  ip_protocol       = "all"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "-1/-1"
  security_group_id = alicloud_security_group.this.id
  cidr_ip           = "0.0.0.0/0"
  description       = "Allow all egress"
}
