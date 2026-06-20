variable "enabled" {
  description = "Whether to create an EIP. Set false if account real-name verification is pending."
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "attachment_mode" {
  description = "EIP attachment mode: 'ecs' attaches to an ECS instance; 'slb' reserves EIP for future SLB use"
  type        = string
  default     = "ecs"

  validation {
    condition     = contains(["ecs", "slb"], var.attachment_mode)
    error_message = "attachment_mode must be either 'ecs' or 'slb'."
  }
}

variable "ecs_instance_id" {
  description = "ECS instance ID when attachment_mode is 'ecs'"
  type        = string
  default     = null
}

variable "slb_instance_id" {
  description = "SLB instance ID when attachment_mode is 'slb' (reserved for future HA)"
  type        = string
  default     = null
}

variable "bandwidth" {
  description = "EIP bandwidth in Mbps"
  type        = number
  default     = 5
}

variable "internet_charge_type" {
  description = "EIP billing method (PayByBandwidth or PayByTraffic)"
  type        = string
  default     = "PayByTraffic"
}

variable "common_tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}
