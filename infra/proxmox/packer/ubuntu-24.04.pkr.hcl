packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

// These variables are declared here and will be populated at runtime by secrets.auto.pkrvars.hcl.
variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type = string
}

variable "cloud_init_user" {
  type        = string
  description = "The username for the initial build user."
}

variable "cloud_init_password" {
  type        = string
  description = "The plaintext password for Packer's SSH communicator."
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "A public SSH key to pre-authorize in the template."
  sensitive   = true
}

locals {
    disk_storage = "A2000"
}

source "proxmox-iso" "ubuntu-autoinstall" {

  # --- Proxmox Connection Settings ---
  proxmox_url              = "${var.proxmox_api_url}"
  username                 = "${var.proxmox_api_token_id}"
  token                    = "${var.proxmox_api_token_secret}"
  insecure_skip_tls_verify = true // For homelab with self-signed certs
  task_timeout = "10m"

  # --- VM General Settings ---
  node                 = "${var.proxmox_node}"
  vm_name              = "ubuntu-2404-lts-cloudinit"
  template_description = "Ubuntu 24.04 LTS Cloud-Init Template"
  tags                 = "ubuntu"

  # --- Hardware Configuration ---
  scsi_controller     = "virtio-scsi-pci"
  cores               = 2
  memory              = 4096 // Increased memory for the installer to run smoothly
  ballooning_minimum  = 1024 // Minimum memory for ballooning

  # --- VM System Settings ---
  qemu_agent = true // Enable the QEMU Guest Agent in the VM's configuration

  # --- VM Cloud-Init Settings ---
  cloud_init              = true
  cloud_init_storage_pool = "${local.disk_storage}"

  # --- VM OS Settings: Boot from the Ubuntu Live Server ISO ---
  boot_iso {
    type             = "scsi"
    iso_storage_pool = "local"
    iso_url          = "https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"
    iso_checksum     = "file:https://releases.ubuntu.com/24.04/SHA256SUMS"
    unmount          = true
  }

  # --- VM Disk Settings ---
  disks {
    type              = "virtio"
    disk_size         = "25G"
    storage_pool      = "${local.disk_storage}" // The target storage for the final VM disk
    format            = "raw"
  }

  # --- VM Network Settings ---
  network_adapters {
    model     = "virtio"
    bridge    = "vmbr0"
    firewall  = "false"
  }

  # --- Autoinstall Boot Process ---
  # These commands are typed into the boot menu to trigger the automated installation.
  boot      = "c"
  boot_wait = "5s"
  boot_command = [
      "<esc><wait>",
      "e<wait>",
      "<down><down><down><end>",
      "<bs><bs><bs><bs><wait>",
      "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
      "<f10><wait>"
  ]

  # Useful for debugging, sometimes lag will require this:
  # boot_key_interval = "500ms"

  # --- Packer's Temporary Web Server for Autoinstall ---
  http_directory = "http" // Serve files from the ./http directory

  # --- Bind IP Address and Port ---
  http_bind_address       = "192.168.1.115"
  http_port_min           = 8802
  http_port_max           = 8802

  # --- SSH Connection Settings for Provisioning ---
  communicator = "ssh"
  ssh_username = "${var.cloud_init_user}" // MUST match the username in http/user-data
  ssh_password = "${var.cloud_init_password}" // MUST match the password in http/user-data
  ssh_timeout  = "30m" // Allow enough time for the VM to boot and be ready for SSH
  ssh_pty      = true // Use a pseudo-terminal for interactive commands
}

// Build Definition to create the VM Template
build {
  name    = "ubuntu-server-autoinstall"
  sources = ["source.proxmox-iso.ubuntu-autoinstall"]

  # --- Post-Installation Provisioning ---
  # These scripts run inside the newly installed OS to prepare it for templating.
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish first boot setup...'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo '...'; sleep 1; done",
      "echo 'Cleaning up for templating...'",
      "sudo rm /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo apt -y autoremove --purge",
      "sudo apt -y clean",
      "sudo apt -y autoclean",
      "sudo cloud-init clean --logs",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "sudo rm -f /etc/netplan/00-installer-config.yaml",
      "sudo sync",
      "echo 'Setup complete. VM is ready for templating.'"
    ]
  }

    # --- Copies the cloud-init configuration file to the VM ---
    provisioner "file" {
        source      = "files/99-pve.cfg"
        destination = "/tmp/99-pve.cfg"
    }

    # --- Moves the cloud-init configuration file to the correct location ---
    provisioner "shell" {
        inline = [ "sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg" ]
    }
}