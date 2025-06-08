# Proxmox Infrastructure Automation

This homelab infrastructure automates the complete lifecycle of Proxmox virtual machines, from template creation to deployment. Using Packer for building standardized VM templates and OpenTofu for declarative infrastructure management, the system provides a secure, reproducible approach to VM provisioning with encrypted secret management through SOPS.

## Key Features

### Security Architecture
- **Encrypted secrets** with SOPS/Age for all sensitive data
- **Memory-only variables** in Packer (zero disk exposure)  
- **Encrypted state files** committed to Git safely
- **Automatic cleanup** of temporary files and credentials

### Modular Design
- **Generic Packer template** supports multiple distributions
- **Reusable VM module** with flexible configuration options
- **Distribution-specific** autoinstall configs (cloud-init/preseed)
- **Scalable architecture** for different workload types

### Automation Features
- **One-command builds** with comprehensive build script
- **Declarative VM management** through configuration files
- **Template integration** via VM ID references
- **Consistent provisioning** across all deployments

## Prerequisites

Before getting started, you'll need several tools installed and proper Proxmox configuration for API access.

| Tool | Purpose | Installation |
|------|---------|-------------|
| **Packer** | VM template automation | [Download](https://www.packer.io/downloads) |
| **OpenTofu** | Infrastructure deployment | [Download](https://opentofu.org/docs/intro/install/) |
| **SOPS** | Secret encryption/decryption | [Install Guide](https://github.com/mozilla/sops) |
| **Age** | Encryption backend for SOPS | [Install Guide](https://github.com/FiloSottile/age) |
| **mkpasswd** | Password hashing | `sudo apt install whois` |

### Proxmox Configuration

Create an API token in the Proxmox web interface under Datacenter → Permissions → API Tokens, then assign it comprehensive permissions including `VM.*`, `Datastore.*`, and `Sys.*`. Store these credentials securely in the encrypted secrets file at `tofu/live/_global/secrets.sops.yaml`.

### Windows WSL2 Setup

If you're running from Windows WSL2, enable mirrored networking and configure firewall rules for the Packer HTTP server:

```powershell
# Enable mirrored networking in .wslconfig
[wsl2]
networkingMode=mirrored

# Open firewall for Packer HTTP server
New-NetFirewallRule -DisplayName "Packer HTTP Server" -Direction Inbound -LocalPort 8802 -Protocol TCP -Action Allow
```

## Project Architecture

The infrastructure separates template creation (Packer) from VM deployment (OpenTofu). Packer builds standardized templates while OpenTofu manages deployment using a modular structure.

```
infra/proxmox/
├── packer/
│   ├── build.sh                    # Main build automation script
│   ├── generic-template.pkr.hcl    # Generic Packer template
│   ├── ubuntu.pkvars.hcl          # Ubuntu 24.04 configuration
│   ├── debian.pkvars.hcl          # Debian 12 configuration
│   ├── http-ubuntu/               # Ubuntu autoinstall files
│   │   ├── user-data.tpl          # Cloud-init template
│   │   └── meta-data              # Metadata file
│   ├── http-debian/               # Debian preseed files
│   │   └── preseed.cfg.tpl        # Preseed template
│   └── files/
│       └── 99-pve.cfg             # Cloud-init Proxmox config
├── tofu/
│   ├── live/
│   │   ├── _global/
│   │   │   └── secrets.sops.yaml  # Encrypted secrets
│   │   └── k8s_nodes/
│   │       ├── main.tf             # VM deployment orchestration
│   │       ├── k8s_nodes.auto.tfvars # VM definitions
│   │       ├── providers.tf        # Provider configuration
│   │       ├── variables.tf        # Input variables
│   │       └── terraform.sops.tfstate # Encrypted state
│   └── modules/
│       └── vm/                    # Reusable VM module
│           ├── main.tf            # Core VM resource
│           ├── variables.tf       # Module inputs
│           ├── outputs.tf         # Module outputs
│           └── providers.tf       # Module providers
```

## Part 1: Template Creation with Packer

Packer automates the creation of standardized VM templates that serve as the foundation for all future deployments. The system uses a generic template architecture that adapts to different operating systems through distribution-specific configuration files.

### Template Configuration System

The core of Packer automation lies in distribution configuration files (`.pkvars.hcl`) that define every aspect of template building. The generic Packer template acts as a universal foundation that adapts to any Linux distribution or specialized systems like Talos Linux through these configuration files.

### Building Templates

The template creation process uses an automated build script that orchestrates the entire Packer workflow:

```bash
cd infra/proxmox/packer

# Build Ubuntu 24.04 template
./build.sh ubuntu

# Build Debian 12 template  
./build.sh debian
```

The build script decrypts secrets from SOPS into memory, generates secure password hashes using mkpasswd, and creates distribution-specific autoinstall files from templates. It downloads ISO images, configures VM hardware according to the distribution profile, and automatically cleans up temporary files.

### Distribution Configuration Examples

Taking a closer look at the Ubuntu configuration (`ubuntu.pkvars.hcl`), you can see how the template system works in practice:

```hcl
# VM Identity and Hardware
vm_id                  = 900
vm_name                = "ubuntu-2404-lts-autoinstall"
cores                  = 2
memory                 = 4096
machine                = "q35"
cpu_type               = "host"

# Storage Configuration  
disk_size              = "25G"
disk_format            = "raw"
storage_pool_disk      = "A2000"
cloud_init_storage_pool = "A2000"

# ISO and Installation
iso_url                = "https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"
iso_checksum           = "file:https://releases.ubuntu.com/24.04/SHA256SUMS"

# Boot Configuration for Ubuntu Autoinstall
boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
]

# HTTP Server for Autoinstall Files
http_directory         = "http-ubuntu"
http_bind_address      = "192.168.1.115"
http_port_min          = 8802

# Provisioning Steps
shell_provisioners = [
  {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 1; done",
      "sudo apt -y autoremove --purge",
      "sudo cloud-init clean --logs"
    ]
  }
]
```

Each distribution requires its own `.pkvars.hcl` file with appropriate settings for ISO sources, boot commands, and installation methods. The system supports different autoinstall approaches while maintaining consistent provisioning outcomes.

### Building Templates

The template creation process uses an automated build script that orchestrates the entire Packer workflow:

```bash
cd infra/proxmox/packer

# Build Ubuntu 24.04 template
./build.sh ubuntu

# Build Debian 12 template  
./build.sh debian
```

The build script decrypts secrets from SOPS into memory, generates secure password hashes using mkpasswd, and creates distribution-specific autoinstall files from templates. It downloads ISO images, configures VM hardware according to the distribution profile, and automatically cleans up temporary files.

| Distribution | VM ID | Template Name | Autoinstall Method |
|-------------|--------|---------------|-------------------|
| Ubuntu 24.04 LTS | 900 | `ubuntu-2404-lts-autoinstall` | Cloud-init autoinstall |
| Debian 12 | 901 | `debian-12-bookworm-autoinstall` | Preseed configuration |

## Part 2: VM Deployment with OpenTofu

Once templates are available, OpenTofu handles deployment using a modular architecture that separates template definitions from VM specifications. The system uses declarative configuration where VMs are defined in files and deployed through standard infrastructure-as-code practices.

### VM Definition System

OpenTofu deployment centers around VM definition files that specify exactly what infrastructure should be created. The `k8s_nodes.auto.tfvars` file demonstrates this approach with both required and optional parameters:

```hcl
kubernetes_nodes = {
  "k8s-aio-01" = {
    # Required: Template Reference (from Packer)
    template_vm_id = 901              # References debian-12-bookworm-autoinstall
    disk_size      = "25G"            # Storage allocation
    storage_pool   = "A2000"          # Proxmox storage pool
    network_bridge = "vmbr0"          # Proxmox bridge
    ip_cidr        = "192.168.1.110/24" # Static IP assignment
    gateway        = "192.168.1.254"  # Network gateway
    
    # Optional: Resource Overrides
    vm_id          = 101              # Custom VM ID (auto-assigned if omitted)
    cores          = 10               # Override template default of 2 cores
    memory         = 16384            # 16GB RAM instead of template's 4GB
    
    # Optional: Network and DNS
    nameservers    = "192.168.1.254,192.168.1.253" # DNS servers
    network_firewall = true           # Enable Proxmox firewall
    
    # Optional: Behavior and Metadata
    tags           = ["k8s", "single-node"] # Organizational tags
    start_on_create = true            # Boot VM after creation
    onboot         = true             # Start with Proxmox host
    protection     = false            # Deletion protection
  }
}
```

The VM module accepts many optional variables including hardware specifications, network configuration, system behavior, and cloud-init settings. Only the template reference, storage, and network parameters are required.

### Available Templates

| Distribution | VM ID | Template Name | Autoinstall Method |
|-------------|--------|---------------|-------------------|
| Ubuntu 24.04 LTS | 900 | `ubuntu-2404-lts-autoinstall` | Cloud-init autoinstall |
| Debian 12 | 901 | `debian-12-bookworm-autoinstall` | Preseed configuration |

### Deployment Process

The deployment workflow follows standard OpenTofu practices with automatic secret integration:

```bash
cd infra/proxmox/tofu/live/k8s_nodes
tofu init
tofu plan
tofu apply
```

OpenTofu automatically decrypts SOPS secrets, clones the specified Packer template by VM ID reference, configures cloud-init with network settings and user accounts, allocates resources, and outputs connection details.

### State Management

OpenTofu state files are stored in the Git repository but secured through SOPS encryption. The `terraform.sops.tfstate` file contains all infrastructure state data in encrypted format, allowing version control while maintaining security.

```bash
# Load age public key into an environment variable
AGE_PUBLIC_KEY=$(grep -o 'age1[a-z0-9]*' ~/.config/sops/age/keys.txt)

# Decrypt tfstate before making any changes
sops --decrypt --age "$AGE_PUBLIC_KEY" terraform.sops.tfstate > terraform.tfstate

# Re-encrypt state after changes
sops --encrypt --age "$AGE_PUBLIC_KEY" terraform.tfstate > terraform.sops.tfstate


```

This approach enables collaborative infrastructure management through Git while ensuring sensitive data like IP addresses and resource IDs remain encrypted at rest.

### Customization Options

The infrastructure supports extensive customization through configuration files. Edit `.pkvars.hcl` files to modify Packer template specifications, update `*.auto.tfvars` files to change VM deployment requirements, or adjust module defaults in `modules/vm/variables.tf` for new baseline configurations.

## Troubleshooting

### Packer Build Issues

**SOPS decryption failures:** 
```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
```

**Missing dependencies:** 
```bash
sudo apt install whois
```

**WSL2 connectivity:** Check mirrored networking in `.wslconfig` and Windows Firewall rules for port 8802

### OpenTofu Deployment Issues

**Template not found:** 
```bash
qm list | grep autoinstall
```

**Secret access problems:** 
```bash
sops -d tofu/live/_global/secrets.sops.yaml
```

**Network conflicts:** Check IP ranges and gateway accessibility

### Debug Commands

```bash
# Packer verbose mode
PACKER_LOG=1 ./build.sh ubuntu

# OpenTofu detailed planning
tofu plan -detailed-exitcode

# State inspection
sops -d terraform.sops.tfstate | jq '.resources'
```

## Deployment Outputs

After successful deployment, retrieve information about your virtual machines:

```bash
tofu output kubernetes_node_details
```

Example output structure:
```json
{
  "k8s-aio-01" = {
    "ip_address" = "192.168.1.110"
    "vm_id" = 101
  }
}
```

Access your deployed VMs using the configured credentials:
```bash
ssh user@192.168.1.110  # Using credentials from SOPS
```

---

**Next Steps**: With your infrastructure deployed, you can proceed to install Kubernetes using k3s, RKE2, or your preferred distribution.