#!/bin/bash
# Base installation script for Arch Linux
# Run from the Arch Linux ISO

set -e  # Stop on error

# ========================================
# CONFIGURATION VARIABLES
# ========================================
# All variables will be configured interactively
DISK=""
HOSTNAME=""
USERNAME=""
TIMEZONE=""
LOCALE=""
KEYMAP=""

# Partitions (will be defined after disk selection)
PART_BOOT=""
PART_SWAP=""
PART_ROOT=""

# ========================================
# FUNCTIONS
# ========================================

print_step() {
    echo ""
    echo "========================================="
    echo ">>> $1"
    echo "========================================="
}

select_disk() {
    print_step "Selecting installation disk"

    echo "Available disks:"
    echo ""
    lsblk -d -o NAME,SIZE,TYPE,VENDOR,MODEL | grep -E "disk"
    echo ""

    while true; do
        read -p "Enter disk name (e.g., sda, nvme0n1, vda): " disk_name

        # Add /dev/ if not already present
        if [[ ! "$disk_name" =~ ^/dev/ ]]; then
            DISK="/dev/$disk_name"
        else
            DISK="$disk_name"
        fi

        # Check that the disk exists
        if [ -b "$DISK" ]; then
            echo ""
            echo "Selected disk: $DISK"
            lsblk "$DISK"
            echo ""

            # Define partitions based on disk type
            if [[ "$DISK" =~ "nvme" ]]; then
                PART_BOOT="${DISK}p1"
                PART_SWAP="${DISK}p2"
                PART_ROOT="${DISK}p3"
            else
                PART_BOOT="${DISK}1"
                PART_SWAP="${DISK}2"
                PART_ROOT="${DISK}3"
            fi

            read -p "Confirm this disk? (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                echo "✓ Disk $DISK selected"
                break
            fi
        else
            echo "✗ Disk $DISK does not exist. Try again."
        fi
    done
}

configure_user() {
    print_step "User configuration"

    # Hostname
    while true; do
        read -p "Computer name (hostname) [archlinux]: " input_hostname
        HOSTNAME="${input_hostname:-archlinux}"

        if [[ "$HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
            echo "✓ Hostname: $HOSTNAME"
            break
        else
            echo "✗ Hostname can only contain letters, numbers, and hyphens"
        fi
    done

    # Username
    while true; do
        read -p "Username: " USERNAME

        if [[ -z "$USERNAME" ]]; then
            echo "✗ Username cannot be empty"
        elif [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            echo "✓ User: $USERNAME"
            break
        else
            echo "✗ Username must start with a lowercase letter"
        fi
    done
}

configure_locale() {
    print_step "Locale configuration"

    read -p "Locale [en_US.UTF-8]: " input_locale
    LOCALE="${input_locale:-en_US.UTF-8}"

    echo "✓ Locale: $LOCALE"
}

configure_keymap() {
    print_step "Keyboard configuration"

    read -p "Keymap [us]: " input_keymap
    KEYMAP="${input_keymap:-us}"

    echo "✓ Keymap: $KEYMAP"
}

configure_timezone() {
    print_step "Timezone configuration"

    read -p "Timezone [America/New_York]: " input_timezone
    TIMEZONE="${input_timezone:-America/New_York}"

    echo "✓ Timezone: $TIMEZONE"
}

show_summary() {
    print_step "Configuration summary"

    echo "Hostname       : $HOSTNAME"
    echo "User           : $USERNAME"
    echo "Locale         : $LOCALE"
    echo "Keymap         : $KEYMAP"
    echo "Timezone       : $TIMEZONE"
    echo "Disk           : $DISK"
    echo "  - Boot       : $PART_BOOT (1GB)"
    echo "  - Swap       : $PART_SWAP (4GB)"
    echo "  - Root       : $PART_ROOT (rest)"
    echo ""

    read -p "Confirm and continue installation? (yes/no): " final_confirm
    if [ "$final_confirm" != "yes" ]; then
        echo "Installation cancelled"
        exit 0
    fi
}

check_uefi() {
    print_step "Checking UEFI mode"
    if [ -d /sys/firmware/efi/efivars ]; then
        echo "✓ UEFI mode detected"
    else
        echo "✗ BIOS mode detected"
        echo "This script requires UEFI mode for systemd-boot"
        echo "Please boot in UEFI mode or use a different bootloader"
        exit 1
    fi
}

check_network() {
    print_step "Checking network connection"
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "✓ Network connection OK"
    else
        echo "✗ No network connection. Configure your connection before continuing."
        exit 1
    fi
}

update_system_clock() {
    print_step "Synchronizing system clock"
    timedatectl set-ntp true
    echo "✓ Clock synchronized"
}

partition_disk() {
    print_step "Partitioning disk $DISK"

    echo "WARNING: Destroying data on $DISK..."

    # GPT partitioning for UEFI with systemd-boot
    # 1: Boot (1GB), 2: Swap (4GB), 3: Root (rest)
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 1GiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary linux-swap 1GiB 5GiB
    parted -s "$DISK" mkpart primary ext4 5GiB 100%

    echo "✓ Disk partitioned"
}

format_partitions() {
    print_step "Formatting partitions"

    mkfs.fat -F32 "$PART_BOOT"
    mkswap "$PART_SWAP"
    mkfs.ext4 -F "$PART_ROOT"

    echo "✓ Partitions formatted"
}

mount_partitions() {
    print_step "Mounting partitions"

    mount "$PART_ROOT" /mnt

    mkdir -p /mnt/boot
    mount "$PART_BOOT" /mnt/boot

    swapon "$PART_SWAP"

    echo "✓ Partitions mounted"
}

install_base_system() {
    print_step "Installing base system with pacstrap"

    pacstrap /mnt base base-devel linux linux-firmware \
        vim nano networkmanager sudo

    echo "✓ Base system installed"
}

generate_fstab() {
    print_step "Generating fstab"
    genfstab -U /mnt >> /mnt/etc/fstab
    echo "✓ fstab generated"
}

configure_system() {
    print_step "Configuring system (chroot)"

    # Get root partition UUID for bootloader
    ROOT_UUID=$(blkid -s UUID -o value "$PART_ROOT")

    cat > /mnt/root/configure.sh << 'CHROOT_EOF'
#!/bin/bash

# Variables (re-injected)
HOSTNAME="__HOSTNAME__"
USERNAME="__USERNAME__"
TIMEZONE="__TIMEZONE__"
LOCALE="__LOCALE__"
KEYMAP="__KEYMAP__"
ROOT_UUID="__ROOT_UUID__"

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Keymap
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Root password
echo "Set root password:"
passwd

# Create user
useradd -m -G wheel,audio,video,storage -s /bin/bash $USERNAME
echo "Set password for $USERNAME:"
passwd $USERNAME

# Sudo for wheel group
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Enable NetworkManager
systemctl enable NetworkManager

# Install systemd-boot
bootctl install

# Create loader configuration
cat > /boot/loader/loader.conf << EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

# Create arch boot entry
cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$ROOT_UUID rw
EOF

# Create fallback boot entry
cat > /boot/loader/entries/arch-fallback.conf << EOF
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options root=UUID=$ROOT_UUID rw
EOF

echo "✓ Configuration complete"

CHROOT_EOF

    # Replace variables in chroot script
    sed -i "s|__HOSTNAME__|$HOSTNAME|g" /mnt/root/configure.sh
    sed -i "s|__USERNAME__|$USERNAME|g" /mnt/root/configure.sh
    sed -i "s|__TIMEZONE__|$TIMEZONE|g" /mnt/root/configure.sh
    sed -i "s|__LOCALE__|$LOCALE|g" /mnt/root/configure.sh
    sed -i "s|__KEYMAP__|$KEYMAP|g" /mnt/root/configure.sh
    sed -i "s|__ROOT_UUID__|$ROOT_UUID|g" /mnt/root/configure.sh

    chmod +x /mnt/root/configure.sh
    arch-chroot /mnt /root/configure.sh
    rm /mnt/root/configure.sh
}

finish_installation() {
    print_step "Finalizing"

    echo ""
    echo "========================================="
    echo "Base installation complete!"
    echo "========================================="
    echo ""
    echo "Next steps:"
    echo "1. Reboot with: reboot"
    echo "2. Remove the installation USB"
    echo "3. Log in with your user"
    echo "4. Run the apps.sh script"
    echo ""

    read -p "Unmount partitions and reboot? (yes/no): " reboot_confirm
    if [ "$reboot_confirm" = "yes" ]; then
        umount -R /mnt
        reboot
    fi
}

# ========================================
# MAIN EXECUTION
# ========================================

main() {
    echo "========================================="
    echo "Arch Linux Base Installation"
    echo "========================================="
    echo ""
    echo "This script will guide you through the installation"
    echo "of Arch Linux on your computer."
    echo ""

    # Interactive configuration
    configure_user
    configure_locale
    configure_keymap
    configure_timezone
    select_disk

    # System checks
    check_uefi
    check_network
    update_system_clock

    # Show summary and ask for confirmation
    show_summary

    # Installation
    partition_disk
    format_partitions
    mount_partitions
    install_base_system
    generate_fstab
    configure_system
    finish_installation
}

# Run installation
main
