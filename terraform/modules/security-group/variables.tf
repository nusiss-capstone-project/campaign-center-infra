variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to attach the security group"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed for SSH (port 22)"
  type        = string
}

variable "allowed_admin_cidr" {
  description = "CIDR allowed for K3s API (port 6443)"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to resources"
  type        = map(string)
  default     = {}
}
