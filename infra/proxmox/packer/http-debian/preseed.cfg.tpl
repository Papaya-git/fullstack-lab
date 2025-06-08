# Debian 12 Preseed Configuration for VM Template

# Localization
d-i debian-installer/language string en
d-i debian-installer/country string FR
d-i debian-installer/locale string en_US.UTF-8
d-i localechooser/supported-locales multiselect en_US.UTF-8, fr_FR.UTF-8

# Keyboard
d-i keyboard-configuration/xkb-keymap select us
d-i keyboard-configuration/variant select intl
d-i console-keymaps-at/keymap select fr-latin9

# Network
d-i netcfg/choose_interface select auto
d-i netcfg/dhcp_timeout string 60
d-i netcfg/get_hostname string debian-template
d-i netcfg/get_domain string localdomain

# Mirror
d-i mirror/country string manual
d-i mirror/http/hostname string ftp.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

# User account
d-i passwd/root-login boolean false
d-i passwd/make-user boolean true
d-i passwd/user-fullname string Template User
d-i passwd/username string ${cloud_init_user}
d-i passwd/user-password-crypted password ${cloud_init_password_hashed}

# Time
d-i clock-setup/utc boolean true
d-i time/zone string Europe/Paris
d-i clock-setup/ntp boolean true

# Partitioning
d-i partman-auto/disk string /dev/vda
d-i partman-auto/method string regular
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-auto/choose_recipe select atomic
d-i partman-auto/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# Base system
d-i base-installer/install-recommends boolean false

# APT
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/use_mirror boolean true
d-i apt-setup/security_host string security.debian.org

# Packages - minimal for fast installation
tasksel tasksel/first multiselect standard
d-i pkgsel/include string openssh-server sudo
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false

# Bootloader
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string default

# Post-installation
d-i preseed/late_command string \
    in-target apt-get update ; \
    in-target apt-get install -y qemu-guest-agent cloud-init sudo ; \
    in-target usermod -aG sudo ${cloud_init_user} ; \
    in-target systemctl enable ssh qemu-guest-agent cloud-init ; \
    echo "${cloud_init_user} ALL=(ALL) NOPASSWD:ALL" >> /target/etc/sudoers.d/packer

# Finish
d-i finish-install/reboot_in_progress note
d-i cdrom-detect/eject boolean true