terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78.1"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.2.0"
    }
  }
}

# Read the global secrets file
data "sops_file" "global_secrets" {
  source_file = "../_global/secrets.sops.yaml"
}

# Configure the Proxmox provider using the decrypted secrets
provider "proxmox" {
  endpoint  = data.sops_file.global_secrets.data["proxmox_api_url"]
  api_token = "${data.sops_file.global_secrets.data["proxmox_api_token_id"]}=${data.sops_file.global_secrets.data["proxmox_api_token_secret"]}"
  insecure  = true
}