# Root-level variable definitions shared across environments.
# The dev environment re-declares these for its own root module usage.

variable "region" {
  description = "Alibaba Cloud region, e.g. cn-hangzhou"
  type        = string
  default     = "cn-hangzhou" # TODO: set your target region
}

variable "zones" {
  description = "Availability zones within the region"
  type        = list(string)
  default     = ["ap-southeast-1a"]
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "campaign-center"
}

variable "environment" {
  description = "Deployment environment (dev, pre, prod)"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "ECS instance type for K3s nodes"
  type        = string
  default     = "ecs.t6-c1m2.large" # TODO: adjust for cost/performance needs
}

variable "image_id" {
  description = "ECS image ID for K3s nodes (must exist in the target region)"
  type        = string
  default     = "ubuntu_22_04_x64_20G_alibase_20260522.vhd" # TODO: verify image ID in your region
}

variable "key_pair_name" {
  description = "Existing ECS key pair name for SSH access"
  type        = string
  default     = "campaign-center-key" # TODO: create/import a key pair in the target region
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH (port 22) to nodes"
  type        = string
  default     = "195.133.129.85/32" # TODO: restrict to your office/VPN CIDR
}

variable "allowed_admin_cidr" {
  description = "CIDR block allowed to access the K3s API (port 6443)"
  type        = string
  default     = "195.133.129.85/32" # TODO: restrict to trusted admin networks
}

variable "master_count" {
  description = "Number of K3s master/control-plane nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of K3s worker nodes"
  type        = number
  default     = 0
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "vswitch_cidrs" {
  description = "VSwitch CIDR block per availability zone"
  type        = map(string)
  default = {
    "ap-southeast-1a" = "10.10.1.0/24"
  }
}

variable "system_disk_category" {
  description = "ECS system disk category (cloud_efficiency, cloud_ssd, cloud_essd, etc.)"
  type        = string
  default     = "cloud_auto"
}

variable "system_disk_size" {
  description = "ECS system disk size in GiB"
  type        = number
  default     = 60
}

variable "system_disk_performance_level" {
  description = "ESSD performance level (PL0, PL1, PL2, PL3). Used when system_disk_category is cloud_essd."
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project    = "campaign-center"
    managed_by = "terraform"
  }
}
