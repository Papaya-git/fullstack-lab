#!/bin/bash
# This script automates the Packer build by securely loading secrets from SOPS,
# hashing the user password, and passing everything directly to Packer as arguments.

set -euo pipefail

# Check if distribution argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <distribution>"
    echo "Available distributions: ubuntu, debian"
    exit 1
fi

DISTRO="$1"
PKVARS_FILE="${DISTRO}.pkvars.hcl"

# Verify the pkvars file exists
if [ ! -f "$PKVARS_FILE" ]; then
    echo "Error: Configuration file '$PKVARS_FILE' not found."
    exit 1
fi

# Cleanup function - now distribution-aware
cleanup() {
    echo "==> Cleaning up temporary files..."
    # Clean up based on distribution
    case "$DISTRO" in
        ubuntu*)
            rm -f http-ubuntu/user-data
            ;;
        debian*)
            rm -f http-debian/preseed.cfg
            ;;
    esac
}
trap cleanup EXIT

# Ensure mkpasswd is installed
if ! command -v mkpasswd &> /dev/null; then
    echo "Error: 'mkpasswd' command not found. Please install the 'whois' package." >&2
    echo "On Debian/Ubuntu: sudo apt-get update && sudo apt-get install whois" >&2
    exit 1
fi

echo "==> Decrypting secrets from SOPS into memory..."

# Read plaintext secrets from SOPS into LOCAL shell variables.
while IFS=':' read -r key value; do
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$key" in
        proxmox_api_url) p_api_url="$value" ;;
        proxmox_node) p_node="$value" ;;
        proxmox_api_token_id) p_token_id="$value" ;;
        proxmox_api_token_secret) p_token_secret="$value" ;;
        cloud_init_user) ci_user="$value" ;;
        cloud_init_password) ci_password="$value" ;;
        ssh_public_key) ssh_key="$value" ;;
    esac
done < <(sops -d ../tofu/live/_global/secrets.yaml | grep -v '^#')

echo "==> Generating hashed password for autoinstall..."
cloud_init_password_hashed=$(mkpasswd -m sha-512 "$ci_password")

# Generate distribution-specific files
case "$DISTRO" in
    ubuntu*)
        echo "==> Generating Ubuntu cloud-init user-data file..."
        cloud_init_password_hashed=$(mkpasswd -m sha-512 "$ci_password")
        export cloud_init_user=${ci_user}
        export cloud_init_password_hashed
        envsubst < http-ubuntu/user-data.tpl > http-ubuntu/user-data
        ;;
    debian*)
        echo "==> Generating Debian preseed file..."
        cloud_init_password_hashed=$(mkpasswd -m sha-512 "$ci_password")
        export cloud_init_user=${ci_user}
        export cloud_init_password_hashed
        envsubst < http-debian/preseed.cfg.tpl > http-debian/preseed.cfg
        ;;
esac

echo "==> Running 'packer init'..."
packer init .

echo "==> Running 'packer build' for $DISTRO..."

packer build -force \
    -var-file="$PKVARS_FILE" \
    -var "proxmox_api_url=${p_api_url}" \
    -var "proxmox_node=${p_node}" \
    -var "proxmox_api_token_id=${p_token_id}" \
    -var "proxmox_api_token_secret=${p_token_secret}" \
    -var "cloud_init_user=${ci_user}" \
    -var "cloud_init_password=${ci_password}" \
    -var "ssh_public_key=${ssh_key}" \
    .

echo "==> Packer build completed for $DISTRO."