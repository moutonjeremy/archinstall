#!/bin/bash
# Post-installation configuration script for Arch Linux
# Run after base installation and first boot
#
# Usage: ./configure.sh [packages_file]
#   packages_file: Optional path to a custom packages list file (default: packages.txt)
#
# Example:
#   ./configure.sh                      # Uses default packages.txt
#   ./configure.sh my-packages.txt      # Uses custom file

set -e  # Stop on error

# ========================================
# CONFIGURATION VARIABLES
# ========================================

# AUR Helper (yay or paru)
AUR_HELPER="yay"

# Default packages file URL
DEFAULT_PACKAGES_URL="https://moutonjeremy.github.io/archinstall/packages.txt"

# Packages file (can be overridden via argument)
# Uses local packages.txt if it exists, otherwise downloads from website
if [ -n "$1" ]; then
    PACKAGES_FILE="$1"
elif [ -f "packages.txt" ]; then
    PACKAGES_FILE="packages.txt"
else
    PACKAGES_FILE="$DEFAULT_PACKAGES_URL"
fi

# Arrays populated from apps file
PACMAN_APPS=()
AUR_APPS=()
CUSTOM_COMMANDS=()

# ========================================
# FUNCTIONS
# ========================================

print_step() {
    echo ""
    echo "========================================="
    echo ">>> $1"
    echo "========================================="
}

check_root() {
    if [ "$EUID" -eq 0 ]; then
        echo "✗ Do not run this script as root"
        echo "Run it as a normal user (with sudo when needed)"
        exit 1
    fi
}

configure_wifi() {
    print_step "WiFi configuration"

    # Check if already connected
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "✓ Already connected to internet"
        return
    fi

    read -p "Configure WiFi? (yes/no): " setup_wifi
    if [ "$setup_wifi" != "yes" ]; then
        echo "Skipping WiFi configuration"
        return
    fi

    # Check if nmcli is available
    if ! command -v nmcli &> /dev/null; then
        echo "✗ NetworkManager not found"
        exit 1
    fi

    # List available networks
    echo "Scanning for networks..."
    nmcli device wifi rescan 2>/dev/null || true
    sleep 2
    nmcli device wifi list

    echo ""
    read -p "Enter WiFi SSID: " WIFI_SSID
    read -sp "Enter WiFi password: " WIFI_PASS
    echo ""

    # Connect
    nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASS"

    # Verify connection
    sleep 2
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "✓ WiFi connected successfully"
    else
        echo "✗ WiFi connection failed"
        exit 1
    fi
}

load_packages_file() {
    print_step "Loading packages from $PACKAGES_FILE"

    # Check if file is a URL
    if [[ "$PACKAGES_FILE" =~ ^https?:// ]]; then
        echo "Downloading packages list from URL..."
        PACKAGES_CONTENT=$(curl -sL "$PACKAGES_FILE")
        if [ $? -ne 0 ] || [ -z "$PACKAGES_CONTENT" ]; then
            echo "✗ Failed to download packages file from $PACKAGES_FILE"
            exit 1
        fi
        echo "✓ Downloaded from $PACKAGES_FILE"
    else
        # Local file
        if [ ! -f "$PACKAGES_FILE" ]; then
            echo "✗ Packages file not found: $PACKAGES_FILE"
            echo ""
            echo "Options:"
            echo "  - Create a packages.txt file in the current directory"
            echo "  - Specify a custom file: ./configure.sh /path/to/my-packages.txt"
            echo "  - Run without args to use the default online list"
            exit 1
        fi
        PACKAGES_CONTENT=$(cat "$PACKAGES_FILE")
        echo "✓ Loaded from local file"
    fi

    # Parse the file
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Trim whitespace
        line=$(echo "$line" | xargs)

        # Check if custom command
        if [[ "$line" =~ ^\[cmd\][[:space:]]* ]]; then
            cmd="${line#\[cmd\]}"
            cmd=$(echo "$cmd" | xargs)
            CUSTOM_COMMANDS+=("$cmd")
        # Check if AUR package
        elif [[ "$line" =~ ^\[aur\][[:space:]]* ]]; then
            pkg="${line#\[aur\]}"
            pkg=$(echo "$pkg" | xargs)
            AUR_APPS+=("$pkg")
        else
            PACMAN_APPS+=("$line")
        fi
    done <<< "$PACKAGES_CONTENT"

    echo "✓ Loaded ${#PACMAN_APPS[@]} pacman packages"
    echo "✓ Loaded ${#AUR_APPS[@]} AUR packages"
    echo "✓ Loaded ${#CUSTOM_COMMANDS[@]} custom commands"
}

update_system() {
    print_step "Updating system"
    sudo pacman -Syu --noconfirm
    echo "✓ System up to date"
}

install_aur_helper() {
    print_step "Installing AUR helper: $AUR_HELPER"

    if command -v $AUR_HELPER &> /dev/null; then
        echo "✓ $AUR_HELPER already installed"
        return
    fi

    # Install build dependencies
    sudo pacman -S --needed --noconfirm git base-devel

    # Clone and install
    cd /tmp
    git clone "https://aur.archlinux.org/${AUR_HELPER}.git"
    cd $AUR_HELPER
    makepkg -si --noconfirm
    cd ~
    rm -rf "/tmp/${AUR_HELPER}"

    echo "✓ $AUR_HELPER installed"
}

install_pacman_apps() {
    print_step "Installing applications via pacman"

    if [ ${#PACMAN_APPS[@]} -eq 0 ]; then
        echo "No pacman applications to install"
        return
    fi

    for app in "${PACMAN_APPS[@]}"; do
        echo "  - $app"
    done

    sudo pacman -S --needed --noconfirm "${PACMAN_APPS[@]}"

    echo "✓ Pacman applications installed"
}

install_aur_apps() {
    print_step "Installing applications via AUR"

    if [ ${#AUR_APPS[@]} -eq 0 ]; then
        echo "No AUR applications to install"
        return
    fi

    for app in "${AUR_APPS[@]}"; do
        echo "  - $app"
    done

    $AUR_HELPER -S --needed --noconfirm "${AUR_APPS[@]}"

    echo "✓ AUR applications installed"
}

run_custom_commands() {
    print_step "Running custom commands"

    if [ ${#CUSTOM_COMMANDS[@]} -eq 0 ]; then
        echo "No custom commands to run"
        return
    fi

    for cmd in "${CUSTOM_COMMANDS[@]}"; do
        echo "Running: $cmd"
        eval "$cmd"
    done

    echo "✓ Custom commands executed"
}

finish_setup() {
    print_step "Finalizing"

    echo ""
    echo "========================================="
    echo "Configuration complete!"
    echo "========================================="
    echo ""

    read -p "Reboot now? (yes/no): " reboot_confirm
    if [ "$reboot_confirm" = "yes" ]; then
        sudo reboot
    fi
}

# ========================================
# MAIN EXECUTION
# ========================================

main() {
    echo "========================================="
    echo "Arch Linux Post-Installation Configuration"
    echo "========================================="

    check_root
    configure_wifi
    load_packages_file
    update_system
    install_aur_helper
    install_pacman_apps
    install_aur_apps
    run_custom_commands
    finish_setup
}

# Run configuration
main
