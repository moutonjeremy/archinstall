#!/bin/bash
# Application installation script for Arch Linux
# Run after base installation and first boot
#
# Usage: ./apps.sh [apps_file]
#   apps_file: Optional path to a custom apps list file (default: apps.txt)
#
# Example:
#   ./apps.sh                    # Uses default apps.txt
#   ./apps.sh my-apps.txt        # Uses custom file

set -e  # Stop on error

# ========================================
# CONFIGURATION VARIABLES
# ========================================

# AUR Helper (yay or paru)
AUR_HELPER="yay"

# Default apps file URL
DEFAULT_APPS_URL="https://moutonjeremy.github.io/archinstall/apps.txt"

# Apps file (can be overridden via argument)
# Uses local apps.txt if it exists, otherwise downloads from website
if [ -n "$1" ]; then
    APPS_FILE="$1"
elif [ -f "apps.txt" ]; then
    APPS_FILE="apps.txt"
else
    APPS_FILE="$DEFAULT_APPS_URL"
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

load_apps_file() {
    print_step "Loading applications from $APPS_FILE"

    # Check if file is a URL
    if [[ "$APPS_FILE" =~ ^https?:// ]]; then
        echo "Downloading apps list from URL..."
        APPS_CONTENT=$(curl -sL "$APPS_FILE")
        if [ $? -ne 0 ] || [ -z "$APPS_CONTENT" ]; then
            echo "✗ Failed to download apps file from $APPS_FILE"
            exit 1
        fi
        echo "✓ Downloaded from $APPS_FILE"
    else
        # Local file
        if [ ! -f "$APPS_FILE" ]; then
            echo "✗ Apps file not found: $APPS_FILE"
            echo ""
            echo "Options:"
            echo "  - Create an apps.txt file in the current directory"
            echo "  - Specify a custom file: ./apps.sh /path/to/my-apps.txt"
            echo "  - Run without args to use the default online list"
            exit 1
        fi
        APPS_CONTENT=$(cat "$APPS_FILE")
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
    done <<< "$APPS_CONTENT"

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
    echo "Application installation complete!"
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
    echo "Arch Linux Application Installation"
    echo "========================================="

    check_root
    load_apps_file
    update_system
    install_aur_helper
    install_pacman_apps
    install_aur_apps
    run_custom_commands
    finish_setup
}

# Run installation
main
