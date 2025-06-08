# -----------------------------------------------------------------------------
# This file contains all the non-secret configuration for the Ubuntu 24.04 template.
# It is used by the 'packer build' command via the -var-file flag in build.sh.
# -----------------------------------------------------------------------------

# --- Proxmox Connection Settings ---
# Note: Insecure skip is fine for homelabs with self-signed certificates.
proxmox_insecure_skip_tls_verify = true
proxmox_task_timeout             = "15m"

# --- VM Identity and Description ---
vm_id                  = 900
vm_name                = "ubuntu-2404-lts-autoinstall"
template_description   = "Ubuntu 24.04 LTS Cloud-Init Template"
tags                   = "ubuntu;cloudinit;packer"

# --- Hardware Configuration ---
machine             = "q35"
os_type             = "l26" # Linux 2.6/3.x/4.x/5.x kernel
cpu_type            = "host"
cores               = 2
memory              = 4096
ballooning_minimum  = 1024
scsi_controller     = "virtio-scsi-single"
qemu_agent_enabled  = true

# --- Cloud-Init Configuration ---
cloud_init_enabled        = true
cloud_init_storage_pool = "A2000" # The storage pool for the cloud-init drive

# --- ISO Configuration ---
iso_disk_type       = "scsi"
iso_storage_pool    = "local"   # The storage pool where Proxmox temporarily caches the ISO 
iso_url             = "https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"
iso_checksum        = "file:https://releases.ubuntu.com/24.04/SHA256SUMS"
unmount_iso         = true

# --- Storage Configuration ---
disk_type           = "virtio"
disk_size           = "25G"
disk_format         = "raw"
storage_pool_disk   = "A2000" # The storage pool for the VM's primary disk

# --- Network Configuration ---
network_model     = "virtio"
network_bridge    = "vmbr0"
network_firewall  = true

# --- Boot Configuration ---
boot                = "c"
boot_wait           = "5s"
boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
]

# --- Autoinstall HTTP Server ---
# These are often not needed unless you have specific network constraints.
# Packer will choose a random port and bind to the correct IP automatically.
http_directory      = "http-ubuntu"
http_bind_address   = "192.168.1.115"
http_port_min       = 8802
http_port_max       = 8802

# --- SSH Communicator ---
communicator = "ssh"
ssh_timeout  = "30m"
ssh_pty      = true

# --- Build Configuration ---
build_name = "ubuntu-2404-lts-autoinstall"

# --- Provisioners ---
shell_provisioners = [
  {
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
  },
  {
    inline = ["sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg"]
  }
]

file_provisioners = [
  {
    source = "files/99-pve.cfg"
    destination = "/tmp/99-pve.cfg"
  }
]