# This file declares the provider requirements for the 'vm' module.

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78.1"
    }
  }
}