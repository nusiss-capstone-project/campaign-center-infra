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

resource "alicloud_vpc" "this" {
  vpc_name   = "${local.name_prefix}-vpc"
  cidr_block = var.vpc_cidr
  tags       = local.tags
}

data "alicloud_zones" "vswitch" {
  available_resource_creation = "VSwitch"
}

resource "alicloud_vswitch" "this" {
  for_each = var.vswitch_cidrs

  vpc_id       = alicloud_vpc.this.id
  cidr_block   = each.value
  zone_id      = each.key
  vswitch_name = "${local.name_prefix}-vswitch-${each.key}"
  tags         = local.tags

  lifecycle {
    precondition {
      condition     = contains(var.zones, each.key)
      error_message = "vswitch_cidrs key \"${each.key}\" must be listed in zones: ${join(", ", var.zones)}."
    }

    precondition {
      condition     = contains(data.alicloud_zones.vswitch.ids, each.key)
      error_message = <<-EOT
        zone "${each.key}" is not available in the active provider region.
        Available zones: ${join(", ", data.alicloud_zones.vswitch.ids)}.
        configured region variable: ${var.region}

        Common causes:
        - ALIBABA_CLOUD_REGION or ALICLOUD_REGION env var overrides provider region
        - region and zone mismatch (e.g. cn-beijing VPC + ap-southeast-1a zone)
      EOT
    }
  }
}
