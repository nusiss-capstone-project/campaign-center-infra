variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "region" {
  description = "Alibaba Cloud region"
  type        = string
}

variable "zones" {
  description = "Availability zones to deploy VSwitches (multi-AZ within one region)"
  type        = list(string)

  validation {
    condition     = length(var.zones) >= 1
    error_message = "At least one zone is required."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "vswitch_cidrs" {
  description = "VSwitch CIDR per zone. Keys must match entries in zones."
  type        = map(string)

  validation {
    condition     = length(var.vswitch_cidrs) >= 1
    error_message = "At least one vswitch CIDR is required."
  }
}

variable "common_tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}
