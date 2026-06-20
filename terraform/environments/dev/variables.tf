variable "region" {
  description = "Alibaba Cloud region"
  type        = string
  default     = "ap-southeast-1"
}

variable "zones" {
  description = "Availability zones for multi-AZ deployment within the region"
  type        = list(string)

  validation {
    condition     = length(var.zones) >= 1
    error_message = "At least one zone is required."
  }
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "campaign-center"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "ECS instance type for K3s nodes"
  type        = string
}

variable "image_id" {
  description = "ECS image ID (must exist in the target region)"
  type        = string
}

variable "key_pair_name" {
  description = "ECS key pair name"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed for SSH (port 22). Override in tfvars or via TF_VAR_allowed_ssh_cidr."
  type        = string
  default     = "0.0.0.0/0" # dev default; restrict to your IP/VPN in prod
}

variable "allowed_admin_cidr" {
  description = "CIDR allowed for K3s API (port 6443). Override in tfvars or via TF_VAR_allowed_admin_cidr."
  type        = string
  default     = "0.0.0.0/0" # dev default; restrict in prod
}

variable "master_count" {
  description = "Number of K3s master nodes"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of K3s worker nodes"
  type        = number
  default     = 0
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.10.0.0/16"
}

variable "vswitch_cidrs" {
  description = "VSwitch CIDR block per availability zone"
  type        = map(string)
}

variable "system_disk_category" {
  description = "ECS system disk category"
  type        = string
  default     = "cloud_essd"
}

variable "system_disk_size" {
  description = "ECS system disk size (GiB)"
  type        = number
  default     = 40
}

variable "system_disk_performance_level" {
  description = "ESSD performance level"
  type        = string
  default     = "PL1"
}

variable "eip_attachment_mode" {
  description = "EIP attachment mode: ecs (single master) or slb (future HA)"
  type        = string
  default     = "ecs"
}

variable "eip_bandwidth" {
  description = "EIP bandwidth in Mbps"
  type        = number
  default     = 5
}

variable "create_eip" {
  description = "Create an EIP for the K3s master. Set false until account real-name verification is complete."
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Additional common tags"
  type        = map(string)
  default     = {}
}
