#!/bin/bash
# Deploys a Proxmox VM. Handles cloud-init specifically if configured.
# Requires a YAML config file and 'yq' (v4+ by Mike Farah).

set -euo pipefail

# --- Variables: Populated by YAML config and CLI overrides ---
# Initialize all to empty to ensure they are primarily sourced from config or CLI
IMAGE_URL="" PROXMOX_ISO_DIR="" VM_MEMORY="" VM_CORES="" NETWORK_BRIDGE=""
STORAGE_POOL="" DISK_RESIZE="" VM_NAME_PREFIX=""
ONBOOT="" START_VM_AFTER_CREATION="" FORCE_DOWNLOAD="false" # Script-level default for FORCE_DOWNLOAD

# Cloud-Init specific
CI_USER="" CI_PASSWORD="" SSH_KEY_PATH="" VM_CICUSTOM_CONFIG=""

# Advanced VM settings
VM_PROVISIONING_METHOD="" VM_OSTYPE="" VM_AGENT_ENABLED="" VM_BALLOON_ENABLED=""
VM_NETWORK_MODEL="" VM_NET0_FIREWALL="" VM_SCSI_CONTROLLER=""
VM_SCSI0_IOTHREAD="" VM_SCSI0_SSD_EMULATION=""
VM_BIOS="" VM_EFI_DISK_STORAGE="" VM_MACHINE_TYPE="" VM_CPU_TYPE=""
VM_VGA_TYPE="" VM_TAGS="" VM_PROTECTION=""

# --- Helper Functions ---
log_info() { echo >&2 "[INFO] $1"; }
log_warn() { echo >&2 "[WARN] $1"; }
log_error() { echo >&2 "[ERROR] $1"; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") -c CONFIG_FILE.yaml [OPTIONS]

Deploys a Proxmox VM using a YAML configuration file.
MANDATORY: -c/--config (YAML file), 'yq' (v4+ by Mike Farah).

Core Options (override YAML):
  -c, --config FILE.yaml   Path to YAML configuration file.
  -u, --image-url URL        Cloud image URL.
  -i, --iso-dir DIR          Proxmox ISO directory for images.
  -m, --memory MB            VM memory in MB.
  -r, --cores NUM            VM cores.
  -b, --bridge NAME          Network bridge (e.g., vmbr0).
  -s, --storage-pool NAME    Proxmox storage pool for VM OS disk.
  -d, --disk-resize SIZE     Disk resize (e.g., "+32G", "50G").
  -p, --vm-name-prefix STR   Prefix for the VM name.
  -o, --onboot VAL           Set VM onboot (true/false or 1/0).
  --start-vm VAL           Start VM after creation (true/false or 1/0).
  -f, --force-download       Force redownload of the cloud image.
  -h, --help                 Show this help message

Provisioning & Cloud-Init Options (override YAML):
  --vm-provisioning-method STR Method: "cloud-init" or "none".
  --ci-user USER             Cloud-init username (if method is "cloud-init").
  --ci-password PASS         Cloud-init password (if method is "cloud-init").
  --ssh-key-path PATH        Path to SSH public key (if method is "cloud-init").
  --vm-cicustom-config STR   Custom cloud-init user data (if method is "cloud-init").

Advanced VM Options (override YAML):
  --vm-ostype STR            Guest OS type (e.g., l26, ubuntu).
  --vm-agent-enabled BOOL    Enable QEMU Guest Agent (true/false).
  --vm-balloon-enabled BOOL  Enable Memory Ballooning (true/false).
  --vm-network-model STR     Network card model for net0 (e.g., virtio).
  --vm-net0-firewall BOOL    Enable Proxmox firewall on net0 (true/false).
  --vm-scsi-controller STR SCSI controller (e.g., virtio-scsi-pci).
  --vm-scsi0-iothread BOOL   Enable iothread for scsi0 (true/false).
  --vm-scsi0-ssd-emulation BOOL Emulate SSD for scsi0 (true/false).
  --vm-bios STR              BIOS type (seabios, ovmf).
  --vm-efi-disk-storage STR  Storage for EFI disk (if bios is ovmf, e.g., local-lvm).
  --vm-machine-type STR      Machine type (i440fx, q35).
  --vm-cpu-type STR          CPU type (kvm64, host).
  --vm-vga-type STR          VGA display type (serial0, std, none).
  --vm-tags STR              Comma-separated Proxmox tags.
  --vm-protection BOOL       Enable VM protection (true/false).
EOF
    exit 0
}

# --- Prerequisite Check ---
if ! command -v yq &> /dev/null; then
    log_error "'yq' command not found. Please install yq (v4+ by Mike Farah)."
fi

# --- Argument Parsing & Configuration Loading ---
CONFIG_FILE_ARG=""
# Temporary _cli_ variables for all configurable options
_cli_image_url="" _cli_proxmox_iso_dir="" _cli_vm_memory="" _cli_vm_cores=""
_cli_network_bridge="" _cli_storage_pool="" _cli_disk_resize=""
_cli_vm_name_prefix="" _cli_onboot="" _cli_start_vm_after_creation=""
_cli_force_download_set=false _cli_vm_provisioning_method=""
_cli_ci_user="" _cli_ci_password="" _cli_ssh_key_path="" _cli_vm_cicustom_config=""
_cli_vm_ostype="" _cli_vm_agent_enabled="" _cli_vm_balloon_enabled=""
_cli_vm_network_model="" _cli_vm_net0_firewall=""
_cli_vm_scsi_controller="" _cli_vm_scsi0_iothread="" _cli_vm_scsi0_ssd_emulation=""
_cli_vm_bios="" _cli_vm_efi_disk_storage=""
_cli_vm_machine_type="" _cli_vm_cpu_type="" _cli_vm_vga_type=""
_cli_vm_tags="" _cli_vm_protection=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config) CONFIG_FILE_ARG="$2"; shift 2 ;;
        -u|--image-url) _cli_image_url="$2"; shift 2 ;;
        -i|--iso-dir) _cli_proxmox_iso_dir="$2"; shift 2 ;;
        -m|--memory) _cli_vm_memory="$2"; shift 2 ;;
        -r|--cores) _cli_vm_cores="$2"; shift 2 ;;
        -b|--bridge) _cli_network_bridge="$2"; shift 2 ;;
        -s|--storage-pool) _cli_storage_pool="$2"; shift 2 ;;
        -d|--disk-resize) _cli_disk_resize="$2"; shift 2 ;;
        -p|--vm-name-prefix) _cli_vm_name_prefix="$2"; shift 2 ;;
        -o|--onboot) _cli_onboot="$2"; shift 2 ;;
        --start-vm) _cli_start_vm_after_creation="$2"; shift 2 ;;
        -f|--force-download) _cli_force_download_set=true; shift ;;
        --vm-provisioning-method) _cli_vm_provisioning_method="$2"; shift 2;;
        --ci-user) _cli_ci_user="$2"; shift 2 ;;
        --ci-password) _cli_ci_password="$2"; shift 2 ;;
        --ssh-key-path) _cli_ssh_key_path="$2"; shift 2 ;;
        --vm-cicustom-config) _cli_vm_cicustom_config="$2"; shift 2;;
        --vm-ostype) _cli_vm_ostype="$2"; shift 2;;
        --vm-agent-enabled) _cli_vm_agent_enabled="$2"; shift 2;;
        --vm-balloon-enabled) _cli_vm_balloon_enabled="$2"; shift 2;;
        --vm-network-model) _cli_vm_network_model="$2"; shift 2;;
        --vm-net0-firewall) _cli_vm_net0_firewall="$2"; shift 2;;
        --vm-scsi-controller) _cli_vm_scsi_controller="$2"; shift 2;;
        --vm-scsi0-iothread) _cli_vm_scsi0_iothread="$2"; shift 2;;
        --vm-scsi0-ssd-emulation) _cli_vm_scsi0_ssd_emulation="$2"; shift 2;;
        --vm-bios) _cli_vm_bios="$2"; shift 2;;
        --vm-efi-disk-storage) _cli_vm_efi_disk_storage="$2"; shift 2;;
        --vm-machine-type) _cli_vm_machine_type="$2"; shift 2;;
        --vm-cpu-type) _cli_vm_cpu_type="$2"; shift 2;;
        --vm-vga-type) _cli_vm_vga_type="$2"; shift 2;;
        --vm-tags) _cli_vm_tags="$2"; shift 2;;
        --vm-protection) _cli_vm_protection="$2"; shift 2;;
        -h|--help) usage ;;
        *) log_error "Unknown option: '$1'. Use -h for help.";;
    esac
done

# Validate mandatory config file argument
if [ -z "$CONFIG_FILE_ARG" ]; then log_error "Config file missing. Use -c or --config."; fi
if [ ! -f "$CONFIG_FILE_ARG" ]; then log_error "Config file '$CONFIG_FILE_ARG' not found."; fi

# Load YAML config
log_info "Loading configuration from YAML file '$CONFIG_FILE_ARG'"
eval "$(yq e 'to_entries | .[] | .key + "=" + (.value | @sh)' "$CONFIG_FILE_ARG")"

# Apply CLI overrides
[ -n "$_cli_image_url" ] && IMAGE_URL="$_cli_image_url"; [ -n "$_cli_proxmox_iso_dir" ] && PROXMOX_ISO_DIR="$_cli_proxmox_iso_dir";
[ -n "$_cli_vm_memory" ] && VM_MEMORY="$_cli_vm_memory"; [ -n "$_cli_vm_cores" ] && VM_CORES="$_cli_vm_cores";
[ -n "$_cli_network_bridge" ] && NETWORK_BRIDGE="$_cli_network_bridge"; [ -n "$_cli_storage_pool" ] && STORAGE_POOL="$_cli_storage_pool";
[ -n "$_cli_disk_resize" ] && DISK_RESIZE="$_cli_disk_resize"; [ -n "$_cli_vm_name_prefix" ] && VM_NAME_PREFIX="$_cli_vm_name_prefix";
[ -n "$_cli_onboot" ] && ONBOOT="$_cli_onboot"; [ -n "$_cli_start_vm_after_creation" ] && START_VM_AFTER_CREATION="$_cli_start_vm_after_creation";
[ "$_cli_force_download_set" = true ] && FORCE_DOWNLOAD="true"; [ -n "$_cli_vm_provisioning_method" ] && VM_PROVISIONING_METHOD="$_cli_vm_provisioning_method";
[ -n "$_cli_ci_user" ] && CI_USER="$_cli_ci_user"; [ -n "$_cli_ci_password" ] && CI_PASSWORD="$_cli_ci_password";
[ -n "$_cli_ssh_key_path" ] && SSH_KEY_PATH="$_cli_ssh_key_path"; [ -n "$_cli_vm_cicustom_config" ] && VM_CICUSTOM_CONFIG="$_cli_vm_cicustom_config";
[ -n "$_cli_vm_ostype" ] && VM_OSTYPE="$_cli_vm_ostype"; [ -n "$_cli_vm_agent_enabled" ] && VM_AGENT_ENABLED="$_cli_vm_agent_enabled";
[ -n "$_cli_vm_balloon_enabled" ] && VM_BALLOON_ENABLED="$_cli_vm_balloon_enabled"; [ -n "$_cli_vm_network_model" ] && VM_NETWORK_MODEL="$_cli_vm_network_model";
[ -n "$_cli_vm_net0_firewall" ] && VM_NET0_FIREWALL="$_cli_vm_net0_firewall"; [ -n "$_cli_vm_scsi_controller" ] && VM_SCSI_CONTROLLER="$_cli_vm_scsi_controller";
[ -n "$_cli_vm_scsi0_iothread" ] && VM_SCSI0_IOTHREAD="$_cli_vm_scsi0_iothread"; [ -n "$_cli_vm_scsi0_ssd_emulation" ] && VM_SCSI0_SSD_EMULATION="$_cli_vm_scsi0_ssd_emulation";
[ -n "$_cli_vm_bios" ] && VM_BIOS="$_cli_vm_bios"; [ -n "$_cli_vm_efi_disk_storage" ] && VM_EFI_DISK_STORAGE="$_cli_vm_efi_disk_storage";
[ -n "$_cli_vm_machine_type" ] && VM_MACHINE_TYPE="$_cli_vm_machine_type"; [ -n "$_cli_vm_cpu_type" ] && VM_CPU_TYPE="$_cli_vm_cpu_type";
[ -n "$_cli_vm_vga_type" ] && VM_VGA_TYPE="$_cli_vm_vga_type"; [ -n "$_cli_vm_tags" ] && VM_TAGS="$_cli_vm_tags";
[ -n "$_cli_vm_protection" ] && VM_PROTECTION="$_cli_vm_protection";

# Expand ~ (tilde) in path variables
for path_var_name in SSH_KEY_PATH PROXMOX_ISO_DIR; do
    current_path_value="${!path_var_name:-}"
    expanded_before_tilde_check="$current_path_value" # Store for logging comparison
    if [[ -n "$current_path_value" ]]; then
        if [[ "$current_path_value" == "~" ]]; then
            printf -v "$path_var_name" '%s' "$HOME"
        elif [[ "${current_path_value#\~}" != "$current_path_value" ]]; then # Starts with ~
            printf -v "$path_var_name" '%s' "${HOME}${current_path_value#\~}" # Prepend $HOME, remove ~
        fi
        if [[ "${!path_var_name}" != "$expanded_before_tilde_check" ]]; then
          log_info "Expanded path for $path_var_name to '${!path_var_name}'"
        fi
    fi
done

# --- Sanity Checks & Setup ---
BASE_CRITICAL_VARS=(
    "IMAGE_URL" "PROXMOX_ISO_DIR" "VM_MEMORY" "VM_CORES" "NETWORK_BRIDGE"
    "STORAGE_POOL" "DISK_RESIZE" "VM_NAME_PREFIX" "ONBOOT" "VM_PROVISIONING_METHOD"
    "START_VM_AFTER_CREATION" "FORCE_DOWNLOAD" "VM_OSTYPE" "VM_AGENT_ENABLED"
    "VM_BALLOON_ENABLED" "VM_NETWORK_MODEL" "VM_NET0_FIREWALL"
    "VM_SCSI_CONTROLLER" "VM_SCSI0_IOTHREAD" "VM_SCSI0_SSD_EMULATION"
    "VM_BIOS" "VM_MACHINE_TYPE" "VM_CPU_TYPE" "VM_VGA_TYPE" "VM_PROTECTION"
    # VM_TAGS, VM_CICUSTOM_CONFIG, VM_EFI_DISK_STORAGE are conditionally critical or optional
)
CI_CRITICAL_VARS=("CI_USER")

ALL_CRITICAL_VARS=("${BASE_CRITICAL_VARS[@]}")
if [[ "${VM_PROVISIONING_METHOD}" == "cloud-init" ]]; then
    ALL_CRITICAL_VARS+=("${CI_CRITICAL_VARS[@]}")
fi
if [[ "$VM_BIOS" == "ovmf" ]]; then
    ALL_CRITICAL_VARS+=("VM_EFI_DISK_STORAGE") # EFI disk storage is critical for OVMF
fi

for var_name in "${ALL_CRITICAL_VARS[@]}"; do
    if [ -z "${!var_name:-}" ]; then
        log_error "Critical var '$var_name' not set. Check YAML ('$CONFIG_FILE_ARG') or CLI."
    fi
done

SUDO_CMD=""
if [ "$EUID" -ne 0 ]; then
    if ! command -v sudo >/dev/null; then log_error "sudo not found (and not root)."; fi
    if ! sudo -v; then log_error "Failed to acquire sudo privileges."; fi
    SUDO_CMD="sudo"
fi
for cmd in wget qm pvesh cut basename mktemp sed; do
    if ! command -v "$cmd" &>/dev/null; then log_error "Required command '$cmd' not found."; fi
done

if [[ "${VM_PROVISIONING_METHOD}" == "cloud-init" ]]; then
    if [ -n "$SSH_KEY_PATH" ] && [ ! -f "$SSH_KEY_PATH" ]; then
        log_warn "Cloud-init: SSH key '$SSH_KEY_PATH' not found. Proceeding without."
        SSH_KEY_PATH=""
    fi
    if [ -z "$CI_PASSWORD" ] && [ -t 0 ]; then
        log_info "Cloud-init: Password not set."
        read -r -s -p "Enter cloud-init password (optional, press Enter to skip): " CI_PASSWORD_PROMPT; echo
        CI_PASSWORD="$CI_PASSWORD_PROMPT"
    fi
    if [ -z "$CI_PASSWORD" ] && { [ -z "$SSH_KEY_PATH" ] || [ ! -f "$SSH_KEY_PATH" ]; }; then
        log_warn "Cloud-init: No password or valid SSH key. VM access may be difficult."
    fi
fi

# --- Image and VM Naming ---
IMAGE_FILENAME=$(basename "$IMAGE_URL")
RELEASE_NAME=""
if [[ "$IMAGE_FILENAME" =~ ^([a-zA-Z0-9_.-]+)(-server)?(-cloudimg|-cloud) ]]; then
    RELEASE_NAME="${BASH_REMATCH[1]}"
else
    RELEASE_NAME=$(echo "$IMAGE_FILENAME" | cut -d'-' -f1)
    log_warn "Using fallback release name '$RELEASE_NAME' from '$IMAGE_FILENAME'."
fi

# --- Main Logic ---
log_info "Starting VM deployment (method: ${VM_PROVISIONING_METHOD}). Release: '$RELEASE_NAME'."
log_info "  Using image: $IMAGE_URL"

TARGET_IMAGE_PATH="$PROXMOX_ISO_DIR/$IMAGE_FILENAME"
if [ ! -d "$PROXMOX_ISO_DIR" ]; then
    log_info "ISO directory '$PROXMOX_ISO_DIR' not found. Creating..."
    $SUDO_CMD mkdir -p "$PROXMOX_ISO_DIR"
fi

TEMP_FILES_TO_CLEANUP=()
cleanup_temp_files() {
    if [ ${#TEMP_FILES_TO_CLEANUP[@]} -gt 0 ]; then
        log_info "Cleaning up temp file(s): ${TEMP_FILES_TO_CLEANUP[*]}"
        rm -f "${TEMP_FILES_TO_CLEANUP[@]}"
    fi
}
trap cleanup_temp_files EXIT SIGINT SIGTERM

if [ "$FORCE_DOWNLOAD" = "true" ] || [ ! -f "$TARGET_IMAGE_PATH" ]; then
    [ "$FORCE_DOWNLOAD" = "true" ] && [ -f "$TARGET_IMAGE_PATH" ] && { log_info "Forcing download..."; $SUDO_CMD rm -f "$TARGET_IMAGE_PATH"; }
    log_info "Downloading '$IMAGE_URL' to '$TARGET_IMAGE_PATH'..."
    TEMP_DOWNLOAD_PATH=$(mktemp "/tmp/${IMAGE_FILENAME}.XXXXXX")
    TEMP_FILES_TO_CLEANUP+=("$TEMP_DOWNLOAD_PATH")
    wget --progress=bar:force -O "$TEMP_DOWNLOAD_PATH" "$IMAGE_URL"
    $SUDO_CMD mv "$TEMP_DOWNLOAD_PATH" "$TARGET_IMAGE_PATH"
else
    log_info "Image '$TARGET_IMAGE_PATH' already exists."
fi

VMID=$($SUDO_CMD pvesh get /cluster/nextid)
if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then log_error "Invalid next VMID: '$VMID'"; fi
log_info "Using VMID: $VMID"
VM_NAME="${VM_NAME_PREFIX}-${RELEASE_NAME}-${VMID}"

if $SUDO_CMD qm status "$VMID" &>/dev/null ; then log_error "VM with ID '$VMID' already exists."; fi
if $SUDO_CMD qm list | grep -qw "name: $VM_NAME"; then
    log_warn "VM with name '$VM_NAME' may exist (different VMID)."
    if [ -t 0 ]; then
        read -r -p "Proceed with name '$VM_NAME'? (Yes/no): " confirm
        if [[ "${confirm,,}" != "yes" ]]; then log_info "Aborting."; exit 0; fi
    fi
fi

# --- Create and Configure VM ---
log_info "Creating VM $VMID ($VM_NAME) with OS Type: $VM_OSTYPE..."
net0_opts_array=()
net0_opts_array+=("model=${VM_NETWORK_MODEL}")
net0_opts_array+=("bridge=${NETWORK_BRIDGE}")
if [[ "$VM_NET0_FIREWALL" == "true" || "$VM_NET0_FIREWALL" == "1" ]]; then
    net0_opts_array+=("firewall=1")
fi
net0_final_opts=$(IFS=,; echo "${net0_opts_array[*]}")


$SUDO_CMD qm create "$VMID" --name "$VM_NAME" --ostype "$VM_OSTYPE" \
    --memory "$VM_MEMORY" --cores "$VM_CORES" \
    --net0 "$net0_final_opts" \
    --scsihw "$VM_SCSI_CONTROLLER" \
    --bios "$VM_BIOS" --machine "$VM_MACHINE_TYPE" --cpu "$VM_CPU_TYPE"

log_info "Importing disk for VM $VMID..."
$SUDO_CMD qm importdisk "$VMID" "$TARGET_IMAGE_PATH" "$STORAGE_POOL" --format qcow2
IMPORTED_DISK_NAME="vm-${VMID}-disk-0"

log_info "Setting base VM configuration for VM $VMID..."
scsi0_opts_array=()
scsi0_opts_array+=("${STORAGE_POOL}:${IMPORTED_DISK_NAME}")
if [[ "$VM_SCSI0_IOTHREAD" == "true" || "$VM_SCSI0_IOTHREAD" == "1" ]]; then scsi0_opts_array+=("iothread=1"); fi
if [[ "$VM_SCSI0_SSD_EMULATION" == "true" || "$VM_SCSI0_SSD_EMULATION" == "1" ]]; then scsi0_opts_array+=("ssd=1"); fi
scsi0_final_opts=$(IFS=,; echo "${scsi0_opts_array[*]}")
$SUDO_CMD qm set "$VMID" --scsi0 "$scsi0_final_opts"

$SUDO_CMD qm resize "$VMID" scsi0 "$DISK_RESIZE"
$SUDO_CMD qm set "$VMID" --boot c --bootdisk scsi0
$SUDO_CMD qm set "$VMID" --serial0 socket --vga "$VM_VGA_TYPE"

# EFI Disk for OVMF
if [[ "$VM_BIOS" == "ovmf" ]]; then
    if [ -n "$VM_EFI_DISK_STORAGE" ]; then
        log_info "Setting up EFI disk (for UEFI variables) on storage '$VM_EFI_DISK_STORAGE' for OVMF."
        $SUDO_CMD qm set "$VMID" --efidisk0 "${VM_EFI_DISK_STORAGE},size=4M,efitype=4m,pre-enrolled-keys=1"
    else
        log_warn "VM_BIOS is ovmf but VM_EFI_DISK_STORAGE is not set in YAML/CLI. Cannot create efidisk0."
    fi
fi

# Agent and Ballooning
agent_config_string="enabled=0"
if [[ "$VM_AGENT_ENABLED" == "true" || "$VM_AGENT_ENABLED" == "1" ]]; then
    agent_config_string="enabled=1,fstrim_cloned_disks=0"
    if [[ "$VM_BALLOON_ENABLED" == "true" || "$VM_BALLOON_ENABLED" == "1" ]]; then
        log_info "Enabling memory ballooning for VM $VMID."
        $SUDO_CMD qm set "$VMID" --balloon "$VM_MEMORY"
    else
        log_info "Disabling memory ballooning for VM $VMID (agent enabled)."
        $SUDO_CMD qm set "$VMID" --balloon 0
    fi
fi
log_info "Setting QEMU Guest Agent: $agent_config_string"
$SUDO_CMD qm set "$VMID" --agent "$agent_config_string"
if ! [[ "$VM_AGENT_ENABLED" == "true" || "$VM_AGENT_ENABLED" == "1" ]]; then
    log_info "QEMU Agent disabled, ensuring ballooning is also off."
    $SUDO_CMD qm set "$VMID" --balloon 0
fi

# --- Provisioning Specific Configuration ---
if [[ "${VM_PROVISIONING_METHOD}" == "cloud-init" ]]; then
    log_info "Applying cloud-init specific configuration for VM $VMID..."
    $SUDO_CMD qm set "$VMID" --ide2 "$STORAGE_POOL:cloudinit"
    $SUDO_CMD qm set "$VMID" --ipconfig0 ip=dhcp

    if [ -n "$CI_USER" ]; then $SUDO_CMD qm set "$VMID" --ciuser "$CI_USER"; fi
    if [ -n "$CI_PASSWORD" ]; then
        log_info "Setting cloud-init password for user '$CI_USER'."
        $SUDO_CMD qm set "$VMID" --cipassword "$CI_PASSWORD"
    fi
    if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
        log_info "Setting cloud-init SSH key from '$SSH_KEY_PATH'."
        KEY_FILE_FOR_QM="$SSH_KEY_PATH"
        if [[ "$SSH_KEY_PATH" != /root/.ssh/* ]] && [[ "$EUID" -ne 0 ]] && ! $SUDO_CMD test -r "$SSH_KEY_PATH"; then
            TEMP_SSH_KEY=$(mktemp "/tmp/sshkey.${VMID}.XXXXXX.pub")
            TEMP_FILES_TO_CLEANUP+=("$TEMP_SSH_KEY")
            cp "$SSH_KEY_PATH" "$TEMP_SSH_KEY" && chmod 0644 "$TEMP_SSH_KEY"
            KEY_FILE_FOR_QM="$TEMP_SSH_KEY"
            log_info "Using temporary SSH key copy: '$KEY_FILE_FOR_QM'."
        fi
        $SUDO_CMD qm set "$VMID" --sshkeys "$KEY_FILE_FOR_QM"
    else
        log_info "No SSH key or key file not found for cloud-init."
    fi
    if [ -n "$VM_CICUSTOM_CONFIG" ]; then
        log_info "Applying custom cloud-init user data from '$VM_CICUSTOM_CONFIG'."
        $SUDO_CMD qm set "$VMID" --cicustom "$VM_CICUSTOM_CONFIG"
    fi
elif [[ "${VM_PROVISIONING_METHOD}" == "none" ]]; then
    log_info "Provisioning method is 'none'. No specific guest OS configuration applied."
else
    log_warn "Unknown VM_PROVISIONING_METHOD: '${VM_PROVISIONING_METHOD}'. No specific configuration applied."
fi

# Tags and Protection (apply generally)
if [ -n "$VM_TAGS" ]; then $SUDO_CMD qm set "$VMID" --tags "$VM_TAGS"; fi
protection_val="0" && { [[ "$VM_PROTECTION" == "true" || "$VM_PROTECTION" == "1" ]] && protection_val="1"; }
$SUDO_CMD qm set "$VMID" --protection "$protection_val"

# VM OnBoot setting
onboot_val="0" && { [[ "$ONBOOT" == "true" || "$ONBOOT" == "1" ]] && onboot_val="1"; }
$SUDO_CMD qm set "$VMID" --onboot "$onboot_val"

# Start VM if configured
start_vm_val="false" && { [[ "$START_VM_AFTER_CREATION" == "true" || "$START_VM_AFTER_CREATION" == "1" ]] && start_vm_val="1"; } # Corrected to assign "1" for true
if [ "$start_vm_val" = "1" ]; then # Compare with "1"
    log_info "Attempting to start VM $VMID..."
    if $SUDO_CMD qm start "$VMID"; then log_info "VM $VMID started."; else log_warn "Failed to start VM $VMID."; fi
else
    log_info "VM $VMID created. Not starting (START_VM_AFTER_CREATION=$START_VM_AFTER_CREATION)."
fi

log_info "--- VM Deployed Successfully ---"
log_info "  VM Name: $VM_NAME (VMID: $VMID)"
log_info "  Console: $SUDO_CMD qm terminal $VMID"
log_info "  Status:  $($SUDO_CMD qm status "$VMID")"
log_info "----------------------------------"

exit 0