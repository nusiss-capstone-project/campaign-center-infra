output "vpc_id" {
  description = "VPC ID"
  value       = alicloud_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = alicloud_vpc.this.cidr_block
}

output "vswitch_ids" {
  description = "Map of availability zone to VSwitch ID"
  value       = { for zone, vswitch in alicloud_vswitch.this : zone => vswitch.id }
}

output "vswitch_cidrs" {
  description = "Map of availability zone to VSwitch CIDR"
  value       = { for zone, vswitch in alicloud_vswitch.this : zone => vswitch.cidr_block }
}

output "vswitch_id" {
  description = "Primary VSwitch ID (first zone in zones list, for backward compatibility)"
  value       = alicloud_vswitch.this[var.zones[0]].id
}

output "available_vswitch_zones" {
  description = "Zones available for VSwitch in the active provider region"
  value       = data.alicloud_zones.vswitch.ids
}
