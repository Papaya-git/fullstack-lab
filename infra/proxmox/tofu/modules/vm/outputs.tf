output "ip_address" {
  description = "The primary IPv4 address of the created VM, as reported by the QEMU agent."
  value       = length(proxmox_virtual_environment_vm.vm.ipv4_addresses) > 1 ? proxmox_virtual_environment_vm.vm.ipv4_addresses[1][0] : null
}

output "vm_id" {
  description = "The unique numeric ID of the created Proxmox VM."
  value       = proxmox_virtual_environment_vm.vm.vm_id
}