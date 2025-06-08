# -----------------------------------------------------------------------------
# This file contains all the non-secret configuration for the Debian 12 template.
# It is used by the 'packer build' command via the -var-file flag in build.sh.
# -----------------------------------------------------------------------------

# --- Proxmox Connection Settings ---
# Note: Insecure skip is fine for homelabs with self-signed certificates.
proxmox_insecure_skip_tls_verify = true
proxmox_task_timeout             = "15m"

# --- VM Identity and Description ---
vm_id                  = 901
vm_name                = "debian-12-bookworm-autoinstall"
template_description   = "Debian 12 Bookworm Cloud-Init Template"
tags                   = "debian;cloudinit;packer"

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
iso_url             = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso"
iso_checksum        = "file:https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS"
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
    "auto ",
    "console-keymaps-at/keymap=us ",
    "console-setup/ask_detect=false ",
    "debconf/frontend=noninteractive ",
    "fb=false ",
    "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg",
    "<enter><wait>"
]

# --- Autoinstall HTTP Server ---
# Using separate directory for Debian preseed files
http_directory      = "http-debian"
http_bind_address   = "192.168.1.115"
http_port_min       = 8802
http_port_max       = 8802

# --- SSH Communicator ---
communicator = "ssh"
ssh_timeout  = "30m"
ssh_pty      = true

# --- Build Configuration ---
build_name = "debian-12-bookworm-autoinstall"

# --- File Provisioners (run first) ---
file_provisioners = [
  {
    source = "files/99-pve.cfg"
    destination = "/tmp/99-pve.cfg"
  }
]

# --- Shell Provisioners (run after files) ---
shell_provisioners = [
  {
    inline = [
      "echo 'Installing cloud-init configuration...'",
      "sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg",
      "sudo systemctl enable cloud-init qemu-guest-agent || echo 'Services already enabled'"
    ]
  },
  {
    inline = [
      "echo 'Cleaning up for template...'",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo apt -y autoremove --purge",
      "sudo apt -y clean",
      "sudo rm -rf /var/lib/dhcp/* /tmp/* /var/tmp/*",
      "sudo sync",
      "echo 'Template ready'"
    ]
  }
]