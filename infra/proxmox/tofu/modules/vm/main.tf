resource "proxmox_virtual_environment_vm" "vm" {
  # VM Identity and Placement
  name      = var.vm_name
  node_name = var.target_node
  tags      = var.tags
  
  # VM Behavior
  started    = var.start_on_create
  protection = var.protection
  
  # Template to clone from
  clone {
    vm_id = var.template_vm_id
  }
  
  # Hardware Configuration
  machine = var.machine
  bios    = var.bios
  
  cpu {
    cores = var.vm_cores
    type  = var.cpu
  }
  
  memory {
    dedicated = var.vm_memory
    floating  = coalesce(var.ballooning_enabled, true) ? var.vm_memory : null
  }
  
  # QEMU Guest Agent
  agent {
    enabled = coalesce(var.agent_enabled, true)
  }
  
  # VGA Configuration
  vga {
    type = var.vga_type
  }
  
  # Storage Configuration - resize the cloned disk
  disk {
    datastore_id = var.storage_pool
    interface    = "virtio0"
    iothread     = coalesce(var.scsi_iothread, false)
    ssd          = coalesce(var.scsi_ssd, false)
    size         = tonumber(trimsuffix(var.disk_size, "G"))
  }
  
  # EFI Disk - created only if 'efi_storage_pool' is set
  dynamic "efi_disk" {
    for_each = var.efi_storage_pool != null ? [1] : []
    content {
      datastore_id = var.efi_storage_pool
      type         = "4m"
    }
  }
  
  # Network Configuration
  network_device {
    bridge   = coalesce(var.network_bridge, "vmbr0")
    model    = coalesce(var.network_model, "virtio")
    firewall = coalesce(var.network_firewall, true)
    enabled  = true
  }
  
  # Cloud-Init Configuration
  initialization {
    # Network configuration
    dynamic "ip_config" {
      for_each = coalesce(var.network_type, "static") == "static" ? [1] : []
      content {
        ipv4 {
          address = var.network_ip_cidr
          gateway = var.network_gateway
        }
      }
    }
    
    dynamic "ip_config" {
      for_each = coalesce(var.network_type, "static") == "dhcp" ? [1] : []
      content {
        ipv4 {
          address = "dhcp"
        }
      }
    }
    
    # DNS configuration
    dynamic "dns" {
      for_each = var.ci_nameservers != null ? [1] : []
      content {
        servers = split(",", var.ci_nameservers)
        domain  = var.ci_searchdomain
      }
    }
    
    # User account configuration
    user_account {
      username = var.ci_user
      password = var.ci_password
      keys     = var.ci_ssh_public_key != null ? [var.ci_ssh_public_key] : []
    }
  }
  
  lifecycle {
    # If we manually change the running state or network in Proxmox, don't let Tofu revert it
    ignore_changes = [started, network_device]
  }
}