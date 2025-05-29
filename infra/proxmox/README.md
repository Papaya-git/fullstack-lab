# Proxmox VM Deployment Automation

This directory provides a robust solution for automating the creation and initial configuration of Virtual Machines on Proxmox VE. The primary goal is to enable consistent, repeatable, and version-controlled VM deployments, aligning with Infrastructure as Code (IaC) and GitOps principles.

## `deploy_proxmox_vm.sh`

This Bash script serves as the engine for VM deployment. It leverages Proxmox VE's `qm` command-line tool and parses its configuration from a user-supplied YAML file, offering a blend of power and ease of use.

### Key Features:

*   **YAML-Driven Configuration:** Define all aspects of your VM (from image source to hardware and provisioning) in a structured YAML file. This allows configurations to be version-controlled in Git, reviewed, and easily replicated.
*   **Cloud Image Optimized:** Streamlines the deployment of VMs using standard cloud images (e.g., Ubuntu Cloud, Debian Cloud, CentOS Cloud), which are typically designed for automated provisioning.
*   **Flexible Guest OS Provisioning:**
    *   **Cloud-Init Integration:** Robust support for `cloud-init`, enabling automated setup of hostname, users, SSH keys, network interfaces, package installation, and execution of custom scripts on first boot. This is the default and recommended method for compatible images.
    *   **Generic Image Support:** Can deploy VMs from images that do not use cloud-init by setting `VM_PROVISIONING_METHOD: "none"`. This allows for manual configuration post-deployment or for images that use alternative mechanisms (e.g., Talos Linux machine configs, custom ISOs).
*   **Extensive Hardware Customization:** Control CPU cores, memory, disk size and properties (SSD emulation, I/O threads), network interface model and firewall status, BIOS type (SeaBIOS/OVMF UEFI), machine type (i440fx/q35), and more, all via the YAML configuration.
*   **Command-Line Overrides:** For quick tests or minor deviations, specific YAML settings can be temporarily overridden using CLI flags when invoking the script.
*   **Prerequisites:** The script relies on `yq` (version 4+ by Mike Farah) to parse YAML files. Ensure it's installed on the system executing the script.

### Workflow & Usage:

1.  **Install `yq`:** If not already present, install `yq` (v4+ Mike Farah version).
    ```bash
    # Example (Debian/Ubuntu): sudo apt install yq
    # Example (macOS): brew install yq
    ```
2.  **Prepare Configuration:**
    *   Copy or adapt an example YAML configuration file (e.g., `deploy_cloud_init_ubuntu.yaml`) to define your desired VM. Store it, for instance, in the `configs/` subdirectory.
    *   **Crucial:** YAML keys (e.g., `IMAGE_URL`) must match the uppercase Bash variable names expected by the script for the `yq` parsing to work correctly.
    *   Carefully review and customize parameters like `IMAGE_URL`, `STORAGE_POOL`, `CI_USER`, `SSH_KEY_PATH`, and hardware settings.
3.  **Make Script Executable:**
    ```bash
    chmod +x deploy_proxmox_vm.sh
    ```
4.  **Deploy the VM:**
    Run the script, providing the path to your YAML configuration file using the mandatory `-c` option.
    ```bash
    ./deploy_proxmox_vm.sh -c configs/your_vm_config.yaml
    ```
    To override a specific setting for a single run:
    ```bash
    ./deploy_proxmox_vm.sh -c configs/your_vm_config.yaml --vm-memory 4096 --vm-cores 4
    ```
5.  **Verify:** Check the Proxmox VE interface and the script's output for the status of the deployment. Access the VM via SSH (if cloud-init with SSH key was used) or the `qm terminal VMID` console.

### Configuration Details:

*   A comprehensive list of all configurable parameters, their purpose, and example values can be found within the comments of the example `deploy_cloud_init_ubuntu.yaml` file.
*   It's recommended to maintain separate YAML configuration files for different VM roles, environments (dev/staging/prod), or operating systems within the `configs/` directory.

### Best Practices:

*   **Version Control:** Keep both `deploy_proxmox_vm.sh` and your YAML configuration files in a Git repository.
*   **Secrets Management:** For sensitive data like `CI_PASSWORD` (if used instead of SSH keys or interactive prompts), consider using a secrets management tool or ensure the YAML file has very restrictive permissions (`chmod 600`).
*   **Idempotency:** The script creates new VMs with unique IDs. It does not inherently manage or update existing VMs by the same name (though it warns if a VM with the target name exists). For full idempotency and state management, consider integrating this script with higher-level automation tools like Ansible or Terraform.

---