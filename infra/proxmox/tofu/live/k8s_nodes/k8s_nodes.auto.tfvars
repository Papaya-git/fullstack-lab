# This file provides the definitions for the Kubernetes nodes we want to create.
# All settings not defined here will use the sane defaults from the 'vm' module.
kubernetes_nodes = {
  # A single All-In-One (AIO) node that will serve as both control-plane and worker.
  "k8s-aio-01" = {
    # --- Required settings for this node ---
    # NOTE: You need to get the template VM ID from your Packer-built template
    # Run this command to find it: qm list | grep "debian-12-bookworm-autoinstall"
    # Replace 901 with the actual VM ID of your template
    template_vm_id  = 901
    
    # Specify the VM ID for the new VM (optional - if not specified, Proxmox auto-assigns)
    vm_id           = 101
    
    disk_size       = "25G"
    storage_pool    = "A2000"
    network_bridge  = "vmbr0"
    ip_cidr         = "192.168.1.110/24"
    gateway         = "192.168.1.254"
    
    # --- Overrides for this specific node (optional) ---
    cores       = 10
    memory      = 16384 # 16GB
    tags        = ["k8s", "single-node"]
    nameservers = "192.168.1.254,192.168.1.253"
    start_on_create = true
  }
}