# This file defines the inputs for the k8s_nodes deployment stack.
variable "kubernetes_nodes" {
  description = "A map of Kubernetes nodes to create. The key of each entry will be the node's name, and the value is an object containing its specific configuration."
  type = map(object({
    # --- Required settings for every node ---
    template_vm_id  = number
    disk_size       = string
    storage_pool    = string
    network_bridge  = string

    # Cloud-Init Network settings (required for 'static' network_type)
    ip_cidr = string
    gateway = string

    # --- Optional settings that will use the sane defaults from the 'vm' module ---
    vm_id              = optional(number)
    cores              = optional(number)
    memory             = optional(number)
    tags               = optional(list(string))
    onboot             = optional(bool)
    start_on_create    = optional(bool)
    protection         = optional(bool)
    bios               = optional(string)
    machine            = optional(string)
    cpu                = optional(string)
    vga_type           = optional(string)
    agent_enabled      = optional(bool)
    ballooning_enabled = optional(bool)
    efi_storage_pool   = optional(string)
    scsi_controller    = optional(string)
    disk_type          = optional(string)
    scsi_iothread      = optional(bool)
    scsi_ssd           = optional(bool)
    network_model      = optional(string)
    network_firewall   = optional(bool)
    os_type            = optional(string)
    network_type       = optional(string)
    nameservers        = optional(string)
    searchdomain       = optional(string)
  }))
}