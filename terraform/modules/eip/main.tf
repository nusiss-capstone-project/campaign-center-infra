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

resource "alicloud_eip_address" "this" {
  count = var.enabled ? 1 : 0

  address_name         = "${local.name_prefix}-eip"
  bandwidth            = var.bandwidth
  internet_charge_type = var.internet_charge_type
  tags                 = local.tags
}

# Attach EIP directly to an ECS instance (dev single-master pattern).
resource "alicloud_eip_association" "ecs" {
  count = var.enabled && var.attachment_mode == "ecs" ? 1 : 0

  allocation_id = alicloud_eip_address.this[0].id
  instance_id   = var.ecs_instance_id
}

# SLB attachment placeholder: when attachment_mode is "slb", the EIP is created
# but not associated here. Associate it with an SLB listener in a future module
# once multi-master HA is implemented.
