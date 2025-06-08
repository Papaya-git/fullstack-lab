#!/bin/bash
# This script automates the Packer build by securely loading secrets from SOPS,
# hashing the user password, and passing everything directly to Packer as arguments.

set -euo pipefail

# Cleanup function to remove generated files even on Ctrl+C or error
cleanup() {
    echo "==> Cleaning up temporary files..."
    rm -f http/user-data
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
# These are NOT exported to the environment, limiting their scope.
# The 'read' loop is a very safe way to parse key-value data.
while IFS=':' read -r key value; do
    # Trim leading/trailing whitespace from value
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Assign to a variable based on the key
    case "$key" in
        proxmox_api_url) p_api_url="$value" ;;
        proxmox_node) p_node="$value" ;;
        proxmox_api_token_id) p_token_id="$value" ;;
        proxmox_api_token_secret) p_token_secret="$value" ;;
        cloud_init_user) ci_user="$value" ;;
        cloud_init_password) ci_password="$value" ;;
        ssh_public_key) ssh_key="$value" ;;
    esac
done < <(sops -d ../tofu/live/_global/secrets.sops.yaml | grep -v '^#')

echo "==> Generating hashed password for autoinstall..."
# Hash the plaintext password for use in the user-data file
# The secret is only in memory for this one command.
cloud_init_password_hashed=$(mkpasswd -m sha-512 "$ci_password")

echo "==> Generating cloud-init user-data file..."
# Generate the user-data file using environment variables
export cloud_init_user=${ci_user}
export cloud_init_password_hashed
envsubst < http/user-data.tpl > http/user-data

echo "==> Running 'packer init'..."
packer init .

echo "==> Running 'packer build' with variables passed directly..."

# Run packer build, passing all values as -var arguments.
# This avoids exporting secrets to the environment.
# The backslashes allow us to break the command across multiple lines for readability.
packer build -force \
    -var "proxmox_api_url=${p_api_url}" \
    -var "proxmox_node=${p_node}" \
    -var "proxmox_api_token_id=${p_token_id}" \
    -var "proxmox_api_token_secret=${p_token_secret}" \
    -var "cloud_init_user=${ci_user}" \
    -var "cloud_init_password=${ci_password}" \
    -var "ssh_public_key=${ssh_key}" \
    .

echo "==> Packer build completed."