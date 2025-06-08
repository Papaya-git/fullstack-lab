packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.3"
      source  = "github.com/badsectorlabs/proxmox"
    }
  }
}

# --- Proxmox API Credentials (from SOPS secrets) ---
variable "proxmox_api_url" { 
  type = string
  sensitive = true
}
variable "proxmox_api_token_id" { 
  type = string
  sensitive = true
}

variable "proxmox_api_token_secret" { 
  type = string
  sensitive = true 
}
variable "proxmox_node" { 
  type = string
  sensitive = true
}

# --- User Credentials (from SOPS secrets) ---
variable "cloud_init_user" { 
  type = string
  sensitive = true 
}

variable "cloud_init_password" { 
  type = string
  sensitive = true 
}
variable "ssh_public_key" { 
  type = string
  sensitive = true
}

# --- Proxmox Connection Settings ---
variable "proxmox_insecure_skip_tls_verify" { type = bool }
variable "proxmox_task_timeout" { type = string }

# --- VM Identity and Description ---
variable "vm_id" { type = number }
variable "vm_name" { type = string }
variable "template_description" { type = string }
variable "tags" { type = string }

# --- Hardware Configuration ---
variable "machine" { type = string }
variable "os_type" { type = string }
variable "cpu_type" { type = string }
variable "cores" { type = number }
variable "memory" { type = number }
variable "ballooning_minimum" { type = number }
variable "qemu_agent_enabled" { type = bool }

# --- Cloud-Init Configuration ---
variable "cloud_init_enabled" { type = bool }
variable "cloud_init_storage_pool" { type = string }

# --- Storage Configuration ---
variable "scsi_controller" { type = string }
variable "disk_type" { type = string }
variable "disk_size" { type = string }
variable "disk_format" { type = string }
variable "storage_pool_disk" { type = string }

# --- Network Configuration ---
variable "network_bridge" { type = string }
variable "network_model" { type = string }
variable "network_firewall" { type = bool }

# --- ISO Configuration ---
variable "iso_disk_type" { type = string }
variable "iso_url" { type = string }
variable "iso_checksum" { type = string }
variable "iso_storage_pool" { type = string }
variable "unmount_iso" { type = bool }

# --- Boot Configuration ---
variable "boot" { type = string }
variable "boot_wait" { type = string }
variable "boot_command" { type = list(string) }

# --- Autoinstall HTTP Server ---
variable "http_directory" { type = string }
variable "http_bind_address" { type = string }
variable "http_port_min" { type = number }
variable "http_port_max" { type = number }

# --- SSH Communicator ---
variable "ssh_timeout" { type = string }
variable "ssh_pty" { type = bool }
variable "communicator" { type = string }

# --- Build Configuration Variables ---
variable "build_name" { 
  type = string 
  default = "generic-autoinstall"
}

variable "shell_provisioners" {
  type = list(object({
    inline = list(string)
  }))
  default = []
}

variable "file_provisioners" {
  type = list(object({
    source = string
    destination = string
  }))
  default = []
}

source "proxmox-iso" "generic-template-autoinstall" {

  # --- Proxmox Connection Settings ---
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = var.proxmox_insecure_skip_tls_verify
  task_timeout             = var.proxmox_task_timeout

  # --- VM General Settings ---
  node                 = var.proxmox_node
  vm_id                = var.vm_id
  vm_name              = var.vm_name
  template_description = var.template_description
  tags                 = var.tags

  # --- Hardware Configuration ---
  machine             = var.machine
  os                  = var.os_type
  cpu_type            = var.cpu_type
  cores               = var.cores
  memory              = var.memory
  ballooning_minimum  = var.ballooning_minimum
  scsi_controller     = var.scsi_controller
  qemu_agent          = var.qemu_agent_enabled

  # --- VM Cloud-Init Settings ---
  cloud_init              = var.cloud_init_enabled
  cloud_init_storage_pool = var.cloud_init_storage_pool

  # --- VM OS Settings: Boot from the ISO image ---
  boot_iso {
    type             = var.iso_disk_type
    iso_storage_pool = var.iso_storage_pool
    iso_url          = var.iso_url
    iso_checksum     = var.iso_checksum
    unmount          = var.unmount_iso
  }

  # --- VM Disk Settings ---
  disks {
    type         = var.disk_type
    disk_size    = var.disk_size
    storage_pool = var.storage_pool_disk
    format       = var.disk_format
  }


  # --- VM Network Settings ---
  network_adapters {
    model    = var.network_model
    bridge   = var.network_bridge
    firewall = var.network_firewall
  }

  # --- Autoinstall Boot Process ---
  # These commands are typed into the boot menu to trigger the automated installation.
  boot         = var.boot
  boot_wait    = var.boot_wait
  boot_command = var.boot_command

  # --- Packer's Temporary Web Server for Autoinstall ---
  http_directory = var.http_directory

  # --- Bind IP Address and Port ---
  http_bind_address       = var.http_bind_address
  http_port_min           = var.http_port_min
  http_port_max           = var.http_port_max

  # --- SSH Connection Settings for Provisioning ---
  communicator = var.communicator
  ssh_username = var.cloud_init_user
  ssh_password = var.cloud_init_password
  ssh_timeout  = var.ssh_timeout
  ssh_pty      = var.ssh_pty
}

build {
  name    = var.build_name
  sources = ["source.proxmox-iso.generic-template-autoinstall"]

  # File provisioners
  dynamic "provisioner" {
    for_each = var.file_provisioners
    labels   = ["file"]
    content {
      source      = provisioner.value.source
      destination = provisioner.value.destination
    }
  }

  # Shell provisioners
  dynamic "provisioner" {
    for_each = var.shell_provisioners
    labels   = ["shell"]
    content {
      inline = provisioner.value.inline
    }
  }
}