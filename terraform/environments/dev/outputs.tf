output "create_eip" {
  description = "Whether EIP creation is enabled (debug: verify terraform reads tfvars correctly)"
  value       = var.create_eip
}

output "configured_region" {
  description = "Region from terraform.tfvars (should match the active provider region)"
  value       = var.region
}

output "configured_zones" {
  description = "Availability zones from terraform.tfvars"
  value       = var.zones
}

output "vswitch_ids" {
  description = "Map of availability zone to VSwitch ID"
  value       = module.network.vswitch_ids
}

output "node_availability_zones" {
  description = "Map of K3s node to its availability zone"
  value       = module.ecs_k3s_nodes.instance_zones
}

output "available_vswitch_zones" {
  description = "Zones actually available under the active provider region"
  value       = module.network.available_vswitch_zones
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "vswitch_id" {
  description = "Primary VSwitch ID (first zone in zones list)"
  value       = module.network.vswitch_id
}

output "security_group_id" {
  description = "Security group ID"
  value       = module.security_group.security_group_id
}

output "k3s_master_instance_ids" {
  description = "K3s master ECS instance IDs"
  value       = module.ecs_k3s_nodes.master_instance_ids
}

output "k3s_worker_instance_ids" {
  description = "K3s worker ECS instance IDs"
  value       = module.ecs_k3s_nodes.worker_instance_ids
}

output "k3s_master_private_ips" {
  description = "Private IPs of K3s master nodes"
  value       = module.ecs_k3s_nodes.master_private_ips
}

output "k3s_master_public_ip" {
  description = "Public EIP attached to the primary K3s master (null when create_eip = false)"
  value       = try(module.k3s_master_eip[0].eip_address, null)
}

output "ssh_command" {
  description = "Example SSH command for the primary master (requires create_eip = true for public IP)"
  value = try(module.k3s_master_eip[0].eip_address, null) != null ? (
    "ssh -i <path-to-private-key> root@${module.k3s_master_eip[0].eip_address}"
  ) : "EIP disabled — use private IP via bastion/VPN: ${try(module.ecs_k3s_nodes.master_private_ips[0], "n/a")}"
}

# Ansible-friendly aliases (read by ansible/scripts/generate-inventory.sh)
output "master_private_ips" {
  description = "Private IPs of K3s master nodes (Ansible inventory)"
  value       = module.ecs_k3s_nodes.master_private_ips
}

output "master_public_ips" {
  description = "Public IPs of K3s master nodes (Ansible inventory)"
  value = compact([
    try(module.k3s_master_eip[0].eip_address, null),
  ])
}

output "worker_private_ips" {
  description = "Private IPs of K3s worker nodes (Ansible inventory)"
  value       = module.ecs_k3s_nodes.worker_private_ips
}

output "worker_public_ips" {
  description = "Public IPs of K3s worker nodes (empty until per-node EIP is added)"
  value       = []
}
