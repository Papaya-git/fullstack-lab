# This file calls our reusable 'vm' module for each entry in the 'kubernetes_nodes' map.
module "k8s_nodes_vms" {
  source   = "../../modules/vm"
  for_each = var.kubernetes_nodes # Loop over the kubernetes_nodes variable

  # --- Pass configuration from the map object to the module ---
  # The map key (e.g., "k8s-aio-01") becomes the VM's name.
  vm_name = each.key
  
  # Get Proxmox node name from the decrypted SOPS data source
  target_node = data.sops_file.global_secrets.data["proxmox_node"]
  
  # Template VM ID - you'll need to get this from your Packer-built template
  # You can find this by running: qm list | grep "debian-12-bookworm-autoinstall"
  template_vm_id = each.value.template_vm_id
  
  # Pass through all other settings from the current item in the loop
  onboot             = coalesce(each.value.onboot, true)
  start_on_create    = coalesce(each.value.start_on_create, false)
  protection         = coalesce(each.value.protection, false)
  tags               = coalesce(each.value.tags, [])
  vm_cores           = coalesce(each.value.cores, 2)
  vm_memory          = coalesce(each.value.memory, 4096)
  disk_size          = each.value.disk_size
  bios               = coalesce(each.value.bios, "seabios")
  efi_storage_pool   = each.value.efi_storage_pool
  machine            = coalesce(each.value.machine, "q35")
  cpu                = coalesce(each.value.cpu, "host")
  vga_type           = coalesce(each.value.vga_type, "std")
  agent_enabled      = coalesce(each.value.agent_enabled, true)
  ballooning_enabled = coalesce(each.value.ballooning_enabled, true)
  network_model      = coalesce(each.value.network_model, "virtio")
  network_firewall   = coalesce(each.value.network_firewall, true)
  scsi_controller    = coalesce(each.value.scsi_controller, "virtio-scsi-single")
  disk_type          = coalesce(each.value.disk_type, "virtio")
  scsi_iothread      = coalesce(each.value.scsi_iothread, false)
  scsi_ssd           = coalesce(each.value.scsi_ssd, false)
  storage_pool       = each.value.storage_pool
  network_bridge     = coalesce(each.value.network_bridge, "vmbr0")
  
  # Pass cloud-init specific values
  network_type      = coalesce(each.value.network_type, "static")
  network_ip_cidr   = each.value.ip_cidr
  network_gateway   = each.value.gateway
  ci_nameservers    = each.value.nameservers
  ci_searchdomain   = each.value.searchdomain
  
  # Pass secrets from the SOPS data source
  ci_user           = data.sops_file.global_secrets.data["cloud_init_user"]
  ci_password       = data.sops_file.global_secrets.data["cloud_init_password"]
  ci_ssh_public_key = data.sops_file.global_secrets.data["ssh_public_key"]
}

# The output block is also renamed for clarity.
output "kubernetes_node_details" {
  description = "Details of all deployed Kubernetes nodes."
  value = {
    for name, node in module.k8s_nodes_vms : name => {
      ip_address = node.ip_address
      vm_id      = node.vm_id
    }
  }
}