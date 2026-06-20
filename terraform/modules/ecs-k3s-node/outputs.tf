output "instance_ids" {
  description = "Map of logical node keys to ECS instance IDs"
  value       = { for k, v in alicloud_instance.k3s_nodes : k => v.id }
}

output "instance_private_ips" {
  description = "Map of logical node keys to private IP addresses"
  value       = { for k, v in alicloud_instance.k3s_nodes : k => v.private_ip }
}

output "instance_zones" {
  description = "Map of logical node keys to availability zones"
  value       = { for k, v in alicloud_instance.k3s_nodes : k => v.availability_zone }
}

output "master_instance_ids" {
  description = "ECS instance IDs for master nodes"
  value       = [for k, v in alicloud_instance.k3s_nodes : v.id if startswith(k, "master-")]
}

output "master_private_ips" {
  description = "Private IPs for master nodes"
  value       = [for k, v in alicloud_instance.k3s_nodes : v.private_ip if startswith(k, "master-")]
}

output "primary_master_instance_id" {
  description = "Instance ID of the first master node (for EIP attachment in dev)"
  value       = try([for k, v in alicloud_instance.k3s_nodes : v.id if startswith(k, "master-")][0], null)
}

output "worker_instance_ids" {
  description = "ECS instance IDs for worker nodes"
  value       = [for k, v in alicloud_instance.k3s_nodes : v.id if startswith(k, "worker-")]
}

output "worker_private_ips" {
  description = "Private IPs for worker nodes"
  value       = [for k, v in alicloud_instance.k3s_nodes : v.private_ip if startswith(k, "worker-")]
}
