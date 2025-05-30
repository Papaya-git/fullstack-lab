#!/bin/bash
# Deploy Proxmox VM with optional cloud-init configuration
# Dependencies: yq (v4+), qm, pvesh, wget

set -euo pipefail

# Script variables (populated from YAML and CLI)
declare -A CONFIG=(
    [IMAGE_URL]=""
    [PROXMOX_ISO_DIR]=""
    [VM_MEMORY]=""
    [VM_CORES]=""
    [NETWORK_BRIDGE]=""
    [STORAGE_POOL]=""
    [DISK_SIZE]=""
    [VM_NAME_PREFIX]=""
    [VM_ONBOOT]=""
    [VM_AUTOSTART]=""
    [FORCE_DOWNLOAD]="false"
    [VM_PROVISIONING]=""
    [NETWORK_TYPE]=""
    [NETWORK_IP]=""
    [NETWORK_GATEWAY]=""
    [NETWORK_DNS]=""
    [NETWORK_DOMAIN]=""
    [CI_USER]=""
    [CI_PASSWORD]=""
    [CI_SSH_KEY]=""
    [CI_CUSTOM_CONFIG]=""
    [VM_OS_TYPE]=""
    [VM_AGENT]=""
    [VM_BALLOON]=""
    [VM_NET_MODEL]=""
    [VM_NET_FIREWALL]=""
    [VM_SCSI_TYPE]=""
    [VM_SCSI_IOTHREAD]=""
    [VM_SCSI_SSD]=""
    [VM_BIOS]=""
    [VM_EFI_STORAGE]=""
    [VM_MACHINE]=""
    [VM_CPU]=""
    [VM_VGA]=""
    [VM_TAGS]=""
    [VM_PROTECTED]=""
)

# Logging functions
log() { echo >&2 "[INFO] $1"; }
warn() { echo >&2 "[WARN] $1"; }
die() { echo >&2 "[ERROR] $1"; exit 1; }

# Show usage
usage() {
    cat <<'EOF'
Usage: deploy-vm.sh -c CONFIG.yaml [OPTIONS]

Deploy a Proxmox VM using YAML configuration.

Required:
  -c, --config FILE       YAML configuration file

Optional overrides:
  -u, --image-url URL     Cloud image URL
  -m, --memory MB         VM memory in MB
  -r, --cores NUM         VM CPU cores
  -f, --force-download    Force image re-download
  -h, --help              Show this help

Network options:
  --network-type TYPE     "dhcp" or "static"
  --network-ip IP/CIDR    Static IP (e.g., 192.168.1.100/24)
  --network-gateway IP    Gateway IP
  --network-dns IPs       DNS servers (comma-separated)

Examples:
  deploy-vm.sh -c ubuntu.yaml
  deploy-vm.sh -c ubuntu.yaml --network-type static --network-ip 192.168.1.100/24
EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local config_file=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config) config_file="$2"; shift 2 ;;
            -u|--image-url) CONFIG[IMAGE_URL]="$2"; shift 2 ;;
            -m|--memory) CONFIG[VM_MEMORY]="$2"; shift 2 ;;
            -r|--cores) CONFIG[VM_CORES]="$2"; shift 2 ;;
            -f|--force-download) CONFIG[FORCE_DOWNLOAD]="true"; shift ;;
            --network-type) CONFIG[NETWORK_TYPE]="$2"; shift 2 ;;
            --network-ip) CONFIG[NETWORK_IP]="$2"; shift 2 ;;
            --network-gateway) CONFIG[NETWORK_GATEWAY]="$2"; shift 2 ;;
            --network-dns) CONFIG[NETWORK_DNS]="$2"; shift 2 ;;
            -h|--help) usage ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    
    [[ -z "$config_file" ]] && die "Config file required. Use -c option."
    [[ ! -f "$config_file" ]] && die "Config file not found: $config_file"
    
    echo "$config_file"
}

# Load YAML configuration
load_config() {
    local config_file="$1"
    local yaml_key value_from_yq unquoted_value # Added unquoted_value
    
    log "Loading configuration from $config_file"
    
    while IFS='=' read -r yaml_key value_from_yq; do
        # Use eval to correctly interpret the shell-escaped value from yq.
        eval "unquoted_value=$value_from_yq"
        
        # Map YAML keys to internal config keys using the unquoted_value
        case "$yaml_key" in
            IMAGE_URL) [[ -z "${CONFIG[IMAGE_URL]}" ]] && CONFIG[IMAGE_URL]="$unquoted_value" ;;
            PROXMOX_ISO_DIR) CONFIG[PROXMOX_ISO_DIR]="$unquoted_value" ;;
            VM_MEMORY) [[ -z "${CONFIG[VM_MEMORY]}" ]] && CONFIG[VM_MEMORY]="$unquoted_value" ;;
            VM_CORES) [[ -z "${CONFIG[VM_CORES]}" ]] && CONFIG[VM_CORES]="$unquoted_value" ;;
            NETWORK_BRIDGE) CONFIG[NETWORK_BRIDGE]="$unquoted_value" ;;
            STORAGE_POOL) CONFIG[STORAGE_POOL]="$unquoted_value" ;;
            DISK_SIZE) CONFIG[DISK_SIZE]="$unquoted_value" ;;
            VM_NAME_PREFIX) CONFIG[VM_NAME_PREFIX]="$unquoted_value" ;;
            VM_ONBOOT) CONFIG[VM_ONBOOT]="$unquoted_value" ;;
            VM_AUTOSTART) CONFIG[VM_AUTOSTART]="$unquoted_value" ;;
            VM_PROVISIONING) CONFIG[VM_PROVISIONING]="$unquoted_value" ;;
            NETWORK_TYPE) [[ -z "${CONFIG[NETWORK_TYPE]}" ]] && CONFIG[NETWORK_TYPE]="$unquoted_value" ;;
            NETWORK_IP) [[ -z "${CONFIG[NETWORK_IP]}" ]] && CONFIG[NETWORK_IP]="$unquoted_value" ;;
            NETWORK_GATEWAY) [[ -z "${CONFIG[NETWORK_GATEWAY]}" ]] && CONFIG[NETWORK_GATEWAY]="$unquoted_value" ;;
            NETWORK_DNS) [[ -z "${CONFIG[NETWORK_DNS]}" ]] && CONFIG[NETWORK_DNS]="$unquoted_value" ;;
            NETWORK_DOMAIN) CONFIG[NETWORK_DOMAIN]="$unquoted_value" ;;
            CI_USER) CONFIG[CI_USER]="$unquoted_value" ;;
            CI_PASSWORD) CONFIG[CI_PASSWORD]="$unquoted_value" ;;
            CI_SSH_KEY) CONFIG[CI_SSH_KEY]="$unquoted_value" ;;
            CI_CUSTOM_CONFIG) CONFIG[CI_CUSTOM_CONFIG]="$unquoted_value" ;;
            VM_OS_TYPE) CONFIG[VM_OS_TYPE]="$unquoted_value" ;;
            VM_AGENT) CONFIG[VM_AGENT]="$unquoted_value" ;;
            VM_BALLOON) CONFIG[VM_BALLOON]="$unquoted_value" ;;
            VM_NET_MODEL) CONFIG[VM_NET_MODEL]="$unquoted_value" ;;
            VM_NET_FIREWALL) CONFIG[VM_NET_FIREWALL]="$unquoted_value" ;;
            VM_SCSI_TYPE) CONFIG[VM_SCSI_TYPE]="$unquoted_value" ;;
            VM_SCSI_IOTHREAD) CONFIG[VM_SCSI_IOTHREAD]="$unquoted_value" ;;
            VM_SCSI_SSD) CONFIG[VM_SCSI_SSD]="$unquoted_value" ;;
            VM_BIOS) CONFIG[VM_BIOS]="$unquoted_value" ;;
            VM_EFI_STORAGE) CONFIG[VM_EFI_STORAGE]="$unquoted_value" ;;
            VM_MACHINE) CONFIG[VM_MACHINE]="$unquoted_value" ;;
            VM_CPU) CONFIG[VM_CPU]="$unquoted_value" ;;
            VM_VGA) CONFIG[VM_VGA]="$unquoted_value" ;;
            VM_TAGS) CONFIG[VM_TAGS]="$unquoted_value" ;;
            VM_PROTECTED) CONFIG[VM_PROTECTED]="$unquoted_value" ;;
        esac
    done < <(yq e 'to_entries | .[] | .key + "=" + (.value | @sh)' "$config_file")
}

# Validate configuration
validate_config() {
    local required_keys=(
        IMAGE_URL PROXMOX_ISO_DIR VM_MEMORY VM_CORES NETWORK_BRIDGE
        STORAGE_POOL DISK_SIZE VM_NAME_PREFIX VM_PROVISIONING
        VM_OS_TYPE VM_NET_MODEL VM_SCSI_TYPE VM_BIOS VM_MACHINE VM_CPU VM_VGA
    )
    
    for key in "${required_keys[@]}"; do
        [[ -z "${CONFIG[$key]}" ]] && die "Missing required config: $key"
    done
    
    # Set defaults
    CONFIG[NETWORK_TYPE]="${CONFIG[NETWORK_TYPE]:-dhcp}"
    CONFIG[VM_ONBOOT]="${CONFIG[VM_ONBOOT]:-false}"
    CONFIG[VM_AUTOSTART]="${CONFIG[VM_AUTOSTART]:-false}"
    CONFIG[VM_AGENT]="${CONFIG[VM_AGENT]:-true}"
    CONFIG[VM_BALLOON]="${CONFIG[VM_BALLOON]:-true}"
    CONFIG[VM_NET_FIREWALL]="${CONFIG[VM_NET_FIREWALL]:-true}"
    CONFIG[VM_SCSI_IOTHREAD]="${CONFIG[VM_SCSI_IOTHREAD]:-true}"
    CONFIG[VM_SCSI_SSD]="${CONFIG[VM_SCSI_SSD]:-true}"
    CONFIG[VM_PROTECTED]="${CONFIG[VM_PROTECTED]:-false}"
    
    # Validate static network config
    if [[ "${CONFIG[NETWORK_TYPE]}" == "static" ]]; then
        [[ -z "${CONFIG[NETWORK_IP]}" ]] && die "Static IP required for static network"
        [[ -z "${CONFIG[NETWORK_GATEWAY]}" ]] && die "Gateway required for static network"
        
        # Validate IP format
        [[ ! "${CONFIG[NETWORK_IP]}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]] && \
            die "Invalid IP format. Use IP/CIDR (e.g., 192.168.1.100/24)"
    fi
    
    # Validate cloud-init config
    if [[ "${CONFIG[VM_PROVISIONING]}" == "cloud-init" ]]; then
        [[ -z "${CONFIG[CI_USER]}" ]] && die "CI_USER required for cloud-init"
    fi
    
    # Validate UEFI config
    if [[ "${CONFIG[VM_BIOS]}" == "ovmf" ]]; then
        [[ -z "${CONFIG[VM_EFI_STORAGE]}" ]] && die "VM_EFI_STORAGE required for UEFI"
    fi
}

# Expand tilde in paths
expand_path() {
    local path="$1"
    [[ "$path" == "~"* ]] && path="${HOME}${path#\~}"
    echo "$path"
}

# Check prerequisites
check_prerequisites() {
    # Check for required commands
    local cmds=(yq wget qm pvesh)
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
    done
    
    # Check sudo if not root
    if [[ $EUID -ne 0 ]]; then
        command -v sudo &>/dev/null || die "sudo required when not running as root"
        sudo -v || die "Failed to acquire sudo privileges"
    fi
}

# Get sudo command if needed
get_sudo() {
    [[ $EUID -ne 0 ]] && echo "sudo" || echo ""
}

# Download cloud image
download_image() {
    local url="${CONFIG[IMAGE_URL]}"
    local iso_dir="${CONFIG[PROXMOX_ISO_DIR]}"
    local filename=$(basename "$url")
    local target="$iso_dir/$filename"
    local sudo_cmd=$(get_sudo)
    
    # Create ISO directory if needed
    [[ ! -d "$iso_dir" ]] && {
        log "Creating ISO directory: $iso_dir"
        $sudo_cmd mkdir -p "$iso_dir"
    }
    
    # Download if forced or missing
    if [[ "${CONFIG[FORCE_DOWNLOAD]}" == "true" ]] || [[ ! -f "$target" ]]; then
        [[ -f "$target" ]] && {
            log "Removing existing image (forced)"
            $sudo_cmd rm -f "$target"
        }
        
        log "Downloading: $url"
        local temp_file=$(mktemp "/tmp/${filename}.XXXXXX")
        wget --progress=bar:force -O "$temp_file" "$url" || die "Download failed"
        $sudo_cmd mv "$temp_file" "$target"
    else
        log "Image already exists: $target"
    fi
    
    echo "$target"
}

# Extract VM name from image
get_vm_name() {
    local image_path="$1"
    local filename=$(basename "$image_path")
    local release
    
    # Try to extract release name intelligently
    if [[ "$filename" =~ ^([a-zA-Z0-9_.-]+)(-server)?(-cloudimg|-cloud) ]]; then
        release="${BASH_REMATCH[1]}"
    else
        release="${filename%%-*}"
    fi
    
    echo "${CONFIG[VM_NAME_PREFIX]}-${release}"
}

# Get next available VM ID
get_next_vmid() {
    local sudo_cmd=$(get_sudo)
    local vmid=$($sudo_cmd pvesh get /cluster/nextid)
    [[ "$vmid" =~ ^[0-9]+$ ]] || die "Invalid VMID: $vmid"
    echo "$vmid"
}

# Create VM
create_vm() {
    local vmid="$1"
    local vm_name="$2"
    local sudo_cmd=$(get_sudo)
    
    log "Creating VM $vmid ($vm_name)"
    
    # Build network options
    local net_opts="model=${CONFIG[VM_NET_MODEL]},bridge=${CONFIG[NETWORK_BRIDGE]}"
    [[ "${CONFIG[VM_NET_FIREWALL]}" == "true" ]] && net_opts+=",firewall=1"
    
    # Create VM
    $sudo_cmd qm create "$vmid" \
        --name "$vm_name" \
        --ostype "${CONFIG[VM_OS_TYPE]}" \
        --memory "${CONFIG[VM_MEMORY]}" \
        --cores "${CONFIG[VM_CORES]}" \
        --net0 "$net_opts" \
        --scsihw "${CONFIG[VM_SCSI_TYPE]}" \
        --bios "${CONFIG[VM_BIOS]}" \
        --machine "${CONFIG[VM_MACHINE]}" \
        --cpu "${CONFIG[VM_CPU]}"
}

# Import and configure disk
configure_disk() {
    local vmid="$1"
    local image_path="$2"
    local sudo_cmd=$(get_sudo)
    
    log "Importing disk for VM $vmid"
    $sudo_cmd qm importdisk "$vmid" "$image_path" "${CONFIG[STORAGE_POOL]}" --format qcow2
    
    # Configure disk
    local disk_opts="${CONFIG[STORAGE_POOL]}:vm-${vmid}-disk-0"
    [[ "${CONFIG[VM_SCSI_IOTHREAD]}" == "true" ]] && disk_opts+=",iothread=1"
    [[ "${CONFIG[VM_SCSI_SSD]}" == "true" ]] && disk_opts+=",ssd=1"
    
    $sudo_cmd qm set "$vmid" --scsi0 "$disk_opts"
    $sudo_cmd qm resize "$vmid" scsi0 "${CONFIG[DISK_SIZE]}"
    $sudo_cmd qm set "$vmid" --boot c --bootdisk scsi0
}

# Configure VM hardware
configure_hardware() {
    local vmid="$1"
    local sudo_cmd=$(get_sudo)
    
    # Basic hardware
    $sudo_cmd qm set "$vmid" --serial0 socket --vga "${CONFIG[VM_VGA]}"
    
    # UEFI disk if needed
    if [[ "${CONFIG[VM_BIOS]}" == "ovmf" ]]; then
        log "Setting up EFI disk"
        $sudo_cmd qm set "$vmid" --efidisk0 "${CONFIG[VM_EFI_STORAGE]}:1,size=4M,efitype=4m,pre-enrolled-keys=1"
    fi
    
    # Agent configuration
    local agent_cfg="enabled=0"
    if [[ "${CONFIG[VM_AGENT]}" == "true" ]]; then
        agent_cfg="enabled=1,fstrim_cloned_disks=0"
        # Set balloon only if agent is enabled
        local balloon_size=$([[ "${CONFIG[VM_BALLOON]}" == "true" ]] && echo "${CONFIG[VM_MEMORY]}" || echo "0")
        $sudo_cmd qm set "$vmid" --balloon "$balloon_size"
    else
        $sudo_cmd qm set "$vmid" --balloon 0
    fi
    $sudo_cmd qm set "$vmid" --agent "$agent_cfg"
    
    # Tags and protection
    [[ -n "${CONFIG[VM_TAGS]}" ]] && $sudo_cmd qm set "$vmid" --tags "${CONFIG[VM_TAGS]}"
    [[ "${CONFIG[VM_PROTECTED]}" == "true" ]] && $sudo_cmd qm set "$vmid" --protection 1
    
    # Boot behavior
    [[ "${CONFIG[VM_ONBOOT]}" == "true" ]] && $sudo_cmd qm set "$vmid" --onboot 1
}

# Configure cloud-init
configure_cloudinit() {
    local vmid="$1"
    local sudo_cmd=$(get_sudo)
    
    log "Configuring cloud-init for VM $vmid"
    $sudo_cmd qm set "$vmid" --ide2 "${CONFIG[STORAGE_POOL]}:cloudinit"
    
    # Network configuration
    if [[ "${CONFIG[NETWORK_TYPE]}" == "static" ]]; then
        log "Setting static IP: ${CONFIG[NETWORK_IP]}"
        $sudo_cmd qm set "$vmid" --ipconfig0 "ip=${CONFIG[NETWORK_IP]},gw=${CONFIG[NETWORK_GATEWAY]}"
        [[ -n "${CONFIG[NETWORK_DNS]}" ]] && $sudo_cmd qm set "$vmid" --nameserver "${CONFIG[NETWORK_DNS]}"
        [[ -n "${CONFIG[NETWORK_DOMAIN]}" ]] && $sudo_cmd qm set "$vmid" --searchdomain "${CONFIG[NETWORK_DOMAIN]}"
    else
        log "Setting DHCP network"
        $sudo_cmd qm set "$vmid" --ipconfig0 "ip=dhcp"
    fi
    
    # User configuration
    $sudo_cmd qm set "$vmid" --ciuser "${CONFIG[CI_USER]}"
    
    # Password (prompt if not set)
    if [[ -z "${CONFIG[CI_PASSWORD]}" ]] && [[ -t 0 ]]; then
        read -r -s -p "Enter cloud-init password (optional): " CI_PASSWORD_INPUT
        echo
        CONFIG[CI_PASSWORD]="$CI_PASSWORD_INPUT"
    fi
    [[ -n "${CONFIG[CI_PASSWORD]}" ]] && $sudo_cmd qm set "$vmid" --cipassword "${CONFIG[CI_PASSWORD]}"
    
    # SSH key
    local ssh_key_path="${CONFIG[CI_SSH_KEY]}"
    if [[ -n "$ssh_key_path" ]]; then
        ssh_key_path=$(expand_path "$ssh_key_path")
        if [[ -f "$ssh_key_path" ]]; then
            log "Setting SSH key from $ssh_key_path"
            # Create temp copy if needed for permissions
            local key_file="$ssh_key_path"
            if [[ ! -r "$ssh_key_path" ]] && [[ $EUID -ne 0 ]]; then
                key_file=$(mktemp "/tmp/sshkey.XXXXXX.pub")
                cp "$ssh_key_path" "$key_file" && chmod 644 "$key_file"
                trap "rm -f $key_file" EXIT
            fi
            $sudo_cmd qm set "$vmid" --sshkeys "$key_file" || warn "Failed to set SSH key"
        else
            warn "SSH key not found: $ssh_key_path"
        fi
    fi
    
    # Custom config
    if [[ -n "${CONFIG[CI_CUSTOM_CONFIG]}" ]]; then
        log "CI_CUSTOM_CONFIG is non-empty, applying: [${CONFIG[CI_CUSTOM_CONFIG]}]"
        $sudo_cmd qm set "$vmid" --cicustom "${CONFIG[CI_CUSTOM_CONFIG]}"
    else
        log "CI_CUSTOM_CONFIG is empty, skipping cicustom."
    fi

}

# Main execution
main() {
    local config_file
    
    # Parse arguments
    config_file=$(parse_args "$@")
    
    # Setup
    check_prerequisites
    load_config "$config_file"
    
    # Expand paths
    CONFIG[PROXMOX_ISO_DIR]=$(expand_path "${CONFIG[PROXMOX_ISO_DIR]}")
    CONFIG[CI_SSH_KEY]=$(expand_path "${CONFIG[CI_SSH_KEY]}")
    
    # Validate
    validate_config
    
    # Download image
    local image_path=$(download_image)
    
    # Get VM details
    local vmid=$(get_next_vmid)
    local vm_name=$(get_vm_name "$image_path")
    vm_name="${vm_name}-${vmid}"
    
    log "Deploying VM: $vm_name (ID: $vmid)"
    
    # Create and configure VM
    create_vm "$vmid" "$vm_name"
    configure_disk "$vmid" "$image_path"
    configure_hardware "$vmid"
    
    # Configure provisioning
    if [[ "${CONFIG[VM_PROVISIONING]}" == "cloud-init" ]]; then
        configure_cloudinit "$vmid"
    fi
    
    # Start VM if requested
    if [[ "${CONFIG[VM_AUTOSTART]}" == "true" ]]; then
        log "Starting VM $vmid"
        local sudo_cmd=$(get_sudo)
        if $sudo_cmd qm start "$vmid"; then
            log "VM started successfully"
        else
            warn "Failed to start VM"
        fi
    fi
    
    # Summary
    local sudo_cmd=$(get_sudo)
    log ""
    log "=== VM DEPLOYED SUCCESSFULLY ==="
    log "  Name: $vm_name (ID: $vmid)"
    log "  Type: ${CONFIG[VM_PROVISIONING]}"
    [[ "${CONFIG[NETWORK_TYPE]}" == "static" ]] && log "  IP: ${CONFIG[NETWORK_IP]}"
    log "  Console: $sudo_cmd qm terminal $vmid"
    log "  Status: $($sudo_cmd qm status $vmid 2>/dev/null || echo "Unknown")"
    log "================================"
    
    return 0
}

# Ensure clean exit
trap 'exit 0' EXIT

# Run
main "$@"