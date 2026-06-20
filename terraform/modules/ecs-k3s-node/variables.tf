variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "zones" {
  description = "Availability zones for round-robin node placement"
  type        = list(string)

  validation {
    condition     = length(var.zones) >= 1
    error_message = "At least one zone is required."
  }
}

variable "vswitch_ids" {
  description = "Map of availability zone to VSwitch ID"
  type        = map(string)
}

variable "security_group_id" {
  description = "Security group ID for ECS instances"
  type        = string
}

variable "instance_type" {
  description = "ECS instance type"
  type        = string
}

variable "image_id" {
  description = "ECS image ID"
  type        = string
}

variable "key_pair_name" {
  description = "ECS key pair name for SSH"
  type        = string
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

variable "internet_max_bandwidth_out" {
  description = "Maximum outbound bandwidth (Mbps). Set to 0 when using EIP."
  type        = number
  default     = 0
}

variable "system_disk_category" {
  description = "System disk category (cloud_efficiency, cloud_ssd, cloud_essd, etc.)"
  type        = string
  default     = "cloud_essd"
}

variable "system_disk_size" {
  description = "System disk size in GiB"
  type        = number
  default     = 40
}

variable "system_disk_performance_level" {
  description = "ESSD performance level (PL0, PL1, PL2, PL3)"
  type        = string
  default     = "PL1"
}

variable "common_tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}
