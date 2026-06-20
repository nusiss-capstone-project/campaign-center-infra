terraform {
  required_version = ">= 1.5.0"

  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.230"
    }
  }
}

provider "alicloud" {
  region = var.region

  # Region resolution order (highest wins): provider block > ALIBABA_CLOUD_REGION > ALICLOUD_REGION > cn-beijing default.
  # If apply hits cn-beijing unexpectedly, run: env | grep -iE 'ALICLOUD|ALIBABA.*REGION'
}

locals {
  common_tags = merge(var.common_tags, {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  })
}

module "network" {
  source = "../../modules/network"

  project_name  = var.project_name
  environment   = var.environment
  region        = var.region
  zones         = var.zones
  vpc_cidr      = var.vpc_cidr
  vswitch_cidrs = var.vswitch_cidrs
  common_tags   = local.common_tags
}

module "security_group" {
  source = "../../modules/security-group"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  allowed_ssh_cidr   = var.allowed_ssh_cidr
  allowed_admin_cidr = var.allowed_admin_cidr
  common_tags        = local.common_tags
}

module "ecs_k3s_nodes" {
  source = "../../modules/ecs-k3s-node"

  project_name                  = var.project_name
  environment                   = var.environment
  zones                         = var.zones
  vswitch_ids                   = module.network.vswitch_ids
  security_group_id             = module.security_group.security_group_id
  instance_type                 = var.instance_type
  image_id                      = var.image_id
  key_pair_name                 = var.key_pair_name
  master_count                  = var.master_count
  worker_count                  = var.worker_count
  system_disk_category          = var.system_disk_category
  system_disk_size              = var.system_disk_size
  system_disk_performance_level = var.system_disk_performance_level
  common_tags                   = local.common_tags
}

module "k3s_master_eip" {
  count  = var.create_eip ? 1 : 0
  source = "../../modules/eip"

  enabled         = true
  project_name    = var.project_name
  environment     = var.environment
  attachment_mode = var.eip_attachment_mode
  ecs_instance_id = module.ecs_k3s_nodes.primary_master_instance_id
  bandwidth       = var.eip_bandwidth
  common_tags     = local.common_tags
}
