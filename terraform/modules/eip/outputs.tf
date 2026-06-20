output "eip_id" {
  description = "EIP allocation ID"
  value       = try(alicloud_eip_address.this[0].id, null)
}

output "eip_address" {
  description = "Public IP address"
  value       = try(alicloud_eip_address.this[0].ip_address, null)
}

output "attachment_mode" {
  description = "Configured attachment mode"
  value       = var.attachment_mode
}

output "enabled" {
  description = "Whether EIP creation is enabled"
  value       = var.enabled
}
