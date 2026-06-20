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

  master_instances = {
    for idx in range(var.master_count) : "master-${idx + 1}" => {
      role = "master"
      name = "${local.name_prefix}-k3s-master-${idx + 1}"
    }
  }

  worker_instances = {
    for idx in range(var.worker_count) : "worker-${idx + 1}" => {
      role = "worker"
      name = "${local.name_prefix}-k3s-worker-${idx + 1}"
    }
  }

  instances = merge(local.master_instances, local.worker_instances)

  # Spread nodes round-robin across zones (masters first, then workers).
  sorted_instance_keys = sort(keys(local.instances))
  instance_zones = {
    for idx, key in local.sorted_instance_keys :
    key => var.zones[idx % length(var.zones)]
  }
}

resource "alicloud_instance" "k3s_nodes" {
  for_each = local.instances

  instance_name              = each.value.name
  host_name                  = replace(each.value.name, "_", "-")
  instance_type              = var.instance_type
  image_id                   = var.image_id
  availability_zone          = local.instance_zones[each.key]
  security_groups            = [var.security_group_id]
  vswitch_id                 = var.vswitch_ids[local.instance_zones[each.key]]
  internet_max_bandwidth_out = var.internet_max_bandwidth_out
  key_name                   = var.key_pair_name

  system_disk_category          = var.system_disk_category
  system_disk_size              = var.system_disk_size
  system_disk_performance_level = var.system_disk_category == "cloud_essd" ? var.system_disk_performance_level : null

  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
    role        = each.value.role
    environment = var.environment
  }))

  tags = merge(local.tags, {
    role = each.value.role
    Name = each.value.name
    zone = local.instance_zones[each.key]
  })
}
