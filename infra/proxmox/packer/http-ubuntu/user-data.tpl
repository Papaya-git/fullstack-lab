#cloud-config
autoinstall:
  version: 1
  
  # Locale and keyboard settings
  locale: en_US.UTF-8
  keyboard:
    layout: us
  
  # Timezone
  timezone: Europe/Paris
  
  # Storage configuration
  storage:
    layout:
      name: direct
    swap:
      size: 0
  
  # SSH configuration
  ssh:
    install-server: true
    allow-pw: true
    disable_root: true
    ssh_quiet_keygen: true
    allow_public_ssh_keys: true
  
  # Package configuration
  packages:
    - qemu-guest-agent
    - sudo
    - curl
    - vim

  # User configuration
  user-data:
    package_update: true
    package_upgrade: true
    users:
      - name: "${cloud_init_user}"
        groups: [adm, sudo]
        lock-passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        passwd: "${cloud_init_password_hashed}"