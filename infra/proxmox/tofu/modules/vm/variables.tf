# --- VM Identity and Placement ---
variable "vm_name" {
  type        = string
  description = "The name for the new virtual machine."
}

variable "target_node" {
  type        = string
  description = "The Proxmox node to deploy the VM on."
}

variable "template_vm_id" {
  type        = number
  description = "The VM ID of the template to clone from."
}

# --- VM Behavior ---
variable "onboot" {
  type        = bool
  description = "Controls whether the VM will be started when the Proxmox host boots."
  default     = true
}

variable "start_on_create" {
  type        = bool
  description = "Controls whether the VM will be started immediately after creation."
  default     = false
}

variable "protection" {
  type        = bool
  description = "If true, the VM will be protected against accidental deletion."
  default     = false
}

variable "tags" {
  type        = list(string)
  description = "A list of tags to apply to the VM for organization."
  default     = []
}

# --- VM Hardware ---
variable "vm_cores" {
  type        = number
  description = "The number of CPU cores allocated to the VM."
  default     = 2
}

variable "vm_memory" {
  type        = number
  description = "The amount of RAM in MB allocated to the VM."
  default     = 4096
}

variable "bios" {
  type        = string
  description = "The firmware type for the VM. 'seabios' for BIOS, 'ovmf' for UEFI."
  default     = "seabios"
}

variable "machine" {
  type        = string
  description = "The virtual machine type. 'q35' is modern."
  default     = "q35"
}

variable "cpu" {
  type        = string
  description = "The CPU type. 'host' passes through host CPU features."
  default     = "host"
}

variable "vga_type" {
  type        = string
  description = "The virtual VGA adapter type."
  default     = "serial0"
}

# --- Guest Agent and Memory ---
variable "agent_enabled" {
  type        = bool
  description = "If true, enables the QEMU Guest Agent interface."
  default     = true
}

variable "ballooning_enabled" {
  type        = bool
  description = "If true, enables memory ballooning."
  default     = true
}

# --- Storage Configuration ---
variable "disk_size" {
  type        = string
  description = "The size of the primary disk (e.g., '50G')."
}

variable "storage_pool" {
  type        = string
  description = "The Proxmox storage pool for the VM's disk."
}

variable "efi_storage_pool" {
  type        = string
  description = "The storage pool for the EFI disk. Required for UEFI."
  default     = null
}

variable "scsi_controller" {
  type        = string
  description = "The type of the virtual SCSI controller."
  default     = "virtio-scsi-single"
}

variable "disk_type" {
  type        = string
  description = "The bus type for the primary disk, e.g., 'scsi' or 'virtio'."
  default     = "virtio"
}

variable "scsi_iothread" {
  type        = bool
  description = "If true, creates a dedicated I/O thread for the disk."
  default     = false
}

variable "scsi_ssd" {
  type        = bool
  description = "If true, the disk is presented to the guest OS as an SSD."
  default     = false
}

# --- Network Configuration ---
variable "network_bridge" {
  type        = string
  description = "The Proxmox network bridge to attach the VM to."
  default     = "vmbr0"
}

variable "network_model" {
  type        = string
  description = "The model of the virtual network card."
  default     = "virtio"
}

variable "network_firewall" {
  type        = bool
  description = "If true, enables the Proxmox firewall on the network interface."
  default     = false
}

# --- Cloud-Init Configuration ---
variable "os_type" {
  type        = string
  description = "The guest OS type. For cloud-init, this should be 'cloud-init'."
  default     = "cloud-init"
}

variable "network_type" {
  type        = string
  description = "The network configuration type: 'static' or 'dhcp'."
  default     = "static"
}

variable "network_ip_cidr" {
  type        = string
  description = "The static IP address and CIDR. Required if network_type is 'static'."
  default     = null
}

variable "network_gateway" {
  type        = string
  description = "The network gateway IP. Required if network_type is 'static'."
  default     = null
}

variable "ci_user" {
  type        = string
  description = "The username to create via cloud-init."
}

variable "ci_password" {
  type        = string
  description = "The password for the cloud-init user."
  sensitive   = true
  default     = null
}

variable "ci_ssh_public_key" {
  type        = string
  description = "The public SSH key to install for the user."
  sensitive   = true
}

variable "ci_nameservers" {
  type        = string
  description = "A comma-separated string of DNS server IPs."
  default     = null
}

variable "ci_searchdomain" {
  type        = string
  description = "The DNS search domain for the guest OS."
  default     = null
}