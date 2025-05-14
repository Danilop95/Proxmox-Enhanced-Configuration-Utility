#!/bin/bash
# ---------------------------------------------------------
# PROXMOX ENHANCED CONFIG UTILITY (PECU)
# -----------------------------------------------------------------------------
#        ██████╗ ███████╗ ██████╗██╗   ██╗
#        ██╔══██╗██╔════╝██╔════╝██║   ██║
#        ██████╔╝█████╗  ██║     ██║   ██║
#        ██╔═══╝ ██╔══╝  ██║     ██║   ██║
#        ██║     ███████╗╚██████╗╚██████╔╝
#        ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝ 
# -----------------------------------------------------------------------------
#
# By Daniel Puente García (Danielop95/DVNILXP)
# Version: 2.0
# Date: 14/5/2025
# Description: This script assists in configuring and managing GPU passthrough on Proxmox systems,
#              including advanced kernel tweaks and AMD detection.
# ---------------------------------------------------------

# Colors for output
RED='\e[0;31m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
YELLOW='\e[0;33m'
NC='\e[0m' # No Color

APP_ID="PECU"
APP_NAME="Proxmox-Enhanced-Configuration-Utility"
AUTHOR="Daniel Puente Garcia — @Danilop95 "
BUILD_DATE="2025-05-14"
BMAC_URL="https://buymeacoffee.com/danilop95ps"
PATRON_URL="https://patreon.com/dvnilxp95"



# Global variables
BACKUP_DIR="/root/backup-script"
STATE_FILE="$BACKUP_DIR/script_state.txt"
LOG_FILE="/var/log/pecu.log"  # Log file location

# Create backup directory with proper ownership and permissions
mkdir -p "$BACKUP_DIR" || { echo -e "${RED}Error: Failed to create backup directory.${NC}"; exit 1; }
chown -R root:root "$BACKUP_DIR"
chmod -R 755 "$BACKUP_DIR"

# Create state file if it doesn't exist
touch "$STATE_FILE" || { echo -e "${RED}Error: Failed to create state file.${NC}"; exit 1; }


# ---------------------------------------------------------
# Function to display a loading banner
# ---------------------------------------------------------
show_loading_banner() {
    clear
    echo -e "${BLUE}┌───────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│   PROXMOX ENHANCED CONFIG UTILITY (PECU)             │${NC}"
    echo -e "${BLUE}└───────────────────────────────────────────────────────┘${NC}"
    echo -e "${GREEN}By: $AUTHOR${NC}"
    echo -e "${GREEN}BuyMeACoffee: $BMAC_URL${NC}\n"
    local banner_lines=(
        ' ██████╗ ███████╗ ██████╗██╗   ██╗'
        ' ██╔══██╗██╔════╝██╔════╝██║   ██║'
        ' ██████╔╝█████╗  ██║     ██║   ██║'
        ' ██╔═══╝ ██╔══╝  ██║     ██║   ██║'
        ' ██║     ███████╗╚██████╗╚██████╔╝'
        ' ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝'
    )
    echo -e "${YELLOW}"
    for line in "${banner_lines[@]}"; do
        printf "  %s\n" "$line"
        sleep 0.04
    done
    echo -e "${NC}"
    sleep 0.25
    clear
}

# ──────────────────────────────────────────────────────────────
# Helpers generales
# ──────────────────────────────────────────────────────────────

pause() {
    read -rsp $'\nPulse ENTER go back...\n' -n1
}

progress() {
    local msg=$1
    { for p in 0 25 50 75 100; do
          echo $p
          echo -e "XXX\n$p %\n$msg\nXXX"
          sleep 0.2
      done
    } | whiptail --gauge "$msg" 8 60 0
}

has_gpu() {
    lspci | grep -qiE 'vga|3d|display'
}


# ---------------------------------------------------------
# Logging Function: Logs messages with timestamps
# ---------------------------------------------------------
log_message() {
    local msg="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "[$timestamp] $msg" | tee -a "$LOG_FILE"
}

# ---------------------------
# Initialize State File
# ---------------------------
initialize_state() {
    log_message "Initializing state..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR" || { log_message "${RED}Error: Failed to create $BACKUP_DIR.${NC}"; exit 1; }
        log_message "${GREEN}Created missing backup directory at $BACKUP_DIR.${NC}"
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        echo "INITIALIZED" > "$STATE_FILE"
        log_message "${GREEN}Created new state file: $STATE_FILE.${NC}"
    else
        log_message "${YELLOW}State file already exists: $STATE_FILE.${NC}"
    fi
}

# ---------------------------
# Check for Root Privileges
# ---------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root (EUID=0).${NC}"
    echo -e "${YELLOW}Please re-run with 'sudo' or switch to the root user.${NC}"
    exit 1
fi

# -------------------------------------------------------------
# Start Logging
# -------------------------------------------------------------
log_message "Starting Proxmox Enhanced Configuration Utility (PECU)..."

# -------------------------------------------------------------
# Check and Display GPU Information (NVIDIA, AMD, Intel)
# -------------------------------------------------------------
check_gpu_installation() {
    log_message "User selected: Check GPU Installation"
    whiptail --title "Check GPU Installation" --msgbox "Checking GPU installation..." 8 50
    local gpu_info
    gpu_info=$(lspci | grep -i 'vga\|3d\|2d')

    if echo "$gpu_info" | grep -iq 'nvidia'; then
        whiptail --title "GPU Detected" --msgbox "NVIDIA GPU detected." 8 40
        check_nvidia_gpu
    elif echo "$gpu_info" | grep -iq 'amd'; then
        whiptail --title "GPU Detected" --msgbox "AMD GPU detected." 8 40
        check_amd_gpu
    elif echo "$gpu_info" | grep -iq 'intel'; then
        whiptail --title "GPU Detected" --msgbox "Intel iGPU detected." 8 40
        check_intel_gpu
    else
        whiptail --title "No GPU" --msgbox "No NVIDIA, AMD, or Intel GPU detected." 8 50
        return
    fi
}

check_intel_gpu() {
    log_message "Checking Intel iGPU status..."
    local intel_gpu_info
    intel_gpu_info=$(lspci | grep -i 'vga\|3d\|2d' | grep -i 'intel')
    whiptail --title "Intel iGPU Status" --msgbox "$intel_gpu_info" 12 60
}

check_nvidia_gpu() {
    log_message "Checking NVIDIA GPU status..."
    if command -v nvidia-smi &> /dev/null; then
        local output
        output=$(nvidia-smi)
        whiptail --title "nvidia-smi Output" --msgbox "$output" 20 70
        if echo "$output" | grep -iq 'Tesla\|A100\|V100\|A30\|A40'; then
            whiptail --title "GPU Type" --msgbox "Detected NVIDIA Data Center GPU." 8 50
        else
            whiptail --title "GPU Type" --msgbox "Detected NVIDIA Gaming GPU." 8 50
        fi
    else
        whiptail --title "Error" --msgbox "nvidia-smi not found. Please install NVIDIA drivers." 8 60
    fi
}

check_amd_gpu() {
    log_message "Checking AMD GPU status..."
    local amd_gpu_info
    amd_gpu_info=$(lshw -C display | grep -i 'amd')
    whiptail --title "AMD GPUs" --msgbox "$amd_gpu_info" 12 60

    if command -v rocm-smi &> /dev/null; then
        local rocm_output
        rocm_output=$(rocm-smi)
        whiptail --title "rocm-smi Output" --msgbox "$rocm_output" 20 70
        if echo "$rocm_output" | grep -iq 'Instinct\|MI50\|MI100\|MI200'; then
            whiptail --title "GPU Type" --msgbox "Detected AMD Data Center GPU." 8 50
        else
            whiptail --title "GPU Type" --msgbox "Detected AMD Gaming GPU." 8 50
        fi
    else
        whiptail --title "Error" --msgbox "rocm-smi not found. Please install AMD ROCm drivers." 8 60
    fi
}

# -------------------------------------------------------------
# Backup / Restore functions for sources.list
# -------------------------------------------------------------
backup_file() {
    log_message "Creating a backup of sources.list"
    if grep -Fxq "BACKUP_CREATED" "$STATE_FILE"; then
        whiptail --title "Backup" --msgbox "A backup has already been created. Skipping..." 8 60
        return
    fi
    mkdir -p "$BACKUP_DIR"
    local backup_files=("${BACKUP_DIR}/sources.list.bak_"*)
    if [[ ${#backup_files[@]} -ge 5 ]]; then
        whiptail --title "Backup Limit" --msgbox "Max backups (5) reached. Remove old ones." 8 60
        return 1
    fi
    local fn="${BACKUP_DIR}/sources.list.bak_$(date +%Y%m%d_%H%M%S)"
    cp "/etc/apt/sources.list" "$fn" || exit 1
    echo "BACKUP_CREATED" >> "$STATE_FILE"
    whiptail --title "Backup Created" --msgbox "Backup saved at $fn" 8 60
}

restore_backup() {
    log_message "Restoring a previous backup of sources.list"
    local files=("${BACKUP_DIR}/sources.list.bak_"*)
    if [[ ${#files[@]} -eq 0 ]]; then
        whiptail --title "Restore" --msgbox "No backups found." 8 40
        return 1
    fi
    local menu_items=()
    for i in "${!files[@]}"; do
        menu_items+=("$i" "$(basename "${files[$i]}")")
    done
    local choice=$(whiptail --title "Restore Backup" --menu "Select a backup:" 15 60 "${#files[@]}" "${menu_items[@]}" 3>&1 1>&2 2>&3)
    cp "${files[$choice]}" /etc/apt/sources.list
    whiptail --title "Restored" --msgbox "Restored ${files[$choice]}" 8 60
}

open_sources_list() {
    log_message "User opening /etc/apt/sources.list with nano."
    nano "/etc/apt/sources.list"
}

line_exists() {
    grep -Fxq "$1" "/etc/apt/sources.list"
}

modify_sources_list() {
    log_message "Modifying sources.list with recommended lines..."
    if grep -Fxq "SOURCES_LIST_MODIFIED" "$STATE_FILE"; then
        whiptail --title "Modify Sources" --msgbox "sources.list already modified." 8 50
        return
    fi
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://ftp.debian.org/debian bullseye main contrib"
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://ftp.debian.org/debian bullseye-updates main contrib"
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://security.debian.org/debian-security bullseye-security main contrib"
    add_to_file_if_not_exists "/etc/apt/sources.list" "# PVE pve-no-subscription repository provided by proxmox.com, NOT recommended for production use"
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription"
    echo "SOURCES_LIST_MODIFIED" >> "$STATE_FILE"
    whiptail --title "Modified" --msgbox "sources.list updated." 8 50
}

# -------------------------------------------------------------
# MSI, IOMMU, and other Advanced Kernel Settings
# -------------------------------------------------------------
add_msi_options() {
    log_message "Adding MSI options for audio..."
    if grep -Fxq "MSI_OPTIONS_ADDED" "$STATE_FILE"; then
        whiptail --title "MSI Options" --msgbox "Already added." 8 40
        return
    fi
    add_to_file_if_not_exists "/etc/modprobe.d/snd-hda-intel.conf" "options snd-hda-intel enable_msi=1"
    echo "MSI_OPTIONS_ADDED" >> "$STATE_FILE"
    whiptail --title "MSI Options" --msgbox "MSI enabled for audio." 8 50
}

enable_iommu() {
    log_message "Enabling IOMMU..."
    if grep -Fxq "IOMMU_ENABLED" "$STATE_FILE"; then
        whiptail --title "IOMMU" --msgbox "Already enabled." 8 40
        return
    fi
    local vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk -F':' '{print $2}' | xargs)
    if [[ -f "/etc/default/grub" ]]; then
        if [[ "$vendor" == "GenuineIntel" ]]; then
            sed -i 's|\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)|\1 intel_iommu=on iommu=pt|' /etc/default/grub
        else
            sed -i 's|\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)|\1 amd_iommu=on iommu=pt|' /etc/default/grub
        fi
        update-grub &>/dev/null
    elif [[ -f "/etc/kernel/cmdline" ]]; then
        if [[ "$vendor" == "GenuineIntel" ]]; then
            sed -i 's|$| intel_iommu=on iommu=pt|' /etc/kernel/cmdline
        else
            sed -i 's|$| amd_iommu=on iommu=pt|' /etc/kernel/cmdline
        fi
        proxmox-boot-tool refresh &>/dev/null
    fi
    echo "IOMMU_ENABLED" >> "$STATE_FILE"
    whiptail --title "IOMMU" --msgbox "IOMMU enabled. Reboot required." 8 50
}

check_iommu() {
    log_message "Checking if IOMMU is enabled"
    local out=$(dmesg | grep -e DMAR -e IOMMU)
    whiptail --title "IOMMU Check" --msgbox "$out" 12 60
}

apply_kernel_configuration() {
    log_message "Applying kernel configuration..."
    if grep -Fxq "KERNEL_CONFIG_APPLIED" "$STATE_FILE"; then
        return
    fi
    update-initramfs -u -k all &>/dev/null
    echo "KERNEL_CONFIG_APPLIED" >> "$STATE_FILE"
}

append_kernel_param() {
    local param="$1"

    # GRUB-based systems
    if [[ -f /etc/default/grub ]]; then
        # only if not yet present
        if ! grep -q "$param" /etc/default/grub; then
            # insert just before the trailing quote
            sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ '"$param"'"/' /etc/default/grub
            update-grub &>/dev/null
            whiptail --title "$APP_ID — Kernel Tweaks" --msgbox \
                "Added \`$param\` to GRUB_CMDLINE. Please reboot to apply." 8 60
        else
            whiptail --title "$APP_ID — Kernel Tweaks" --msgbox \
                "Parameter \`$param\` is already set in GRUB_CMDLINE." 8 60
        fi

    # systemd-boot (proxmox-boot-tool) systems
    elif [[ -f /etc/kernel/cmdline ]]; then
        if ! grep -q "$param" /etc/kernel/cmdline; then
            sed -i 's|"$||; s|$| '"$param"'"|' /etc/kernel/cmdline
            proxmox-boot-tool refresh &>/dev/null
            whiptail --title "$APP_ID — Kernel Tweaks" --msgbox \
                "Added \`$param\` to kernel cmdline. Please reboot to apply." 8 60
        else
            whiptail --title "$APP_ID — Kernel Tweaks" --msgbox \
                "Parameter \`$param\` is already set in kernel cmdline." 8 60
        fi
    fi

    ask_for_reboot
}
# Continuación de PECU con menús Whiptail

ask_for_reboot() {
    log_message "Prompting user for reboot..."
    if whiptail --title "Reboot" --yesno "Reboot now?" 8 40; then
        log_message "User chose to reboot."
        reboot
    else
        log_message "Reboot postponed."
    fi
}

add_to_file_if_not_exists() {
    local file="$1"
    local entry="$2"
    if ! grep -Fxq "$entry" "$file"; then
        echo "$entry" >> "$file"
        log_message "Added '$entry' to $file"
    fi
}

search_gpu_device() {
    log_message "Listing PCI devices"
    local gpu_list
    gpu_list=$(lspci | grep -iE 'vga|3d|display')

    # Use --scrollbox so users can page through long lists.
    whiptail --title "Available GPUs" --scrollbox "$gpu_list" 20 70
}

# Prompt for PCI ID of the GPU, showing a list of available devices above the input field.
read_gpu_id() {
    log_message "Prompting for GPU ID"

    # Gather the list once for embedding in the prompt.
    local gpu_list
    gpu_list=$(lspci | grep -iE 'vga|3d|display')

    local prompt=$'Available GPU devices:\n'"$gpu_list"$'\n\nEnter PCI ID (0000:xx:xx.x):'

    # Big input box to display list + input field; handle Cancel properly.
    GPU_ID=$(whiptail --title "GPU Device ID" --inputbox "$prompt" 20 80 \
        3>&1 1>&2 2>&3) || return 1

    # Validate PCI syntax: domain:bus.device.function
    if ! [[ "$GPU_ID" =~ ^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{2}\.[0-9A-Fa-f]$ ]]; then
        whiptail --title "Error" --msgbox "Invalid PCI ID format: $GPU_ID" 8 60
        return 1
    fi

    # Lookup vendor/device code; abort if lookup fails.
    GPU_VENDOR_ID=$(lspci -n -s "$GPU_ID" | awk '{print $3}') || {
        whiptail --title "Error" --msgbox "PCI ID not found: $GPU_ID" 8 60
        return 1
    }

    # Let the user confirm the vendor/device ID.
    whiptail --title "Vendor/Device" \
            --msgbox "Vendor/Device ID: $GPU_VENDOR_ID" 8 60
}


classic_passthrough() {
    log_message "Classic passthrough"
    search_gpu_device
    read_gpu_id || return

    # Map vendor to blacklist entries
    case "$GPU_VENDOR_ID" in
        10de)  # NVIDIA
            add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist nouveau"
            add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist nvidia"
            ;;
        1002)  # AMD
            add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist radeon"
            add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist amdgpu"
            ;;
        *)     # Unknown vendor
            whiptail --title "Warning" \
                --msgbox "Unrecognized vendor ID: $GPU_VENDOR_ID\nProceeding without driver blacklisting." 10 60
            ;;
    esac

    # Always add vfio config, even if blacklist was skipped.
    add_to_file_if_not_exists "/etc/modprobe.d/vfio.conf" \
        "options vfio-pci ids=$GPU_VENDOR_ID disable_vga=1"

    apply_kernel_configuration
    echo "PASSTHROUGH_CONFIGURED" >> "$STATE_FILE"

    whiptail --title "Done" --msgbox "Classic passthrough configured." 8 50
    ask_for_reboot
}

driverctl_passthrough() {
    log_message "Driverctl passthrough"
    install_driverctl

    # Prompt method selector
    local choice
    choice=$(whiptail --title "Passthrough Method" --menu "Select:" 10 50 2 \
        M "Manual select (show list first)" \
        S "Skip listing" \
        3>&1 1>&2 2>&3) || return

    # If user wants manual list, show devices again
    [[ $choice == M ]] && search_gpu_device

    # Reuse read_gpu_id() to get PCI_ID
    read_gpu_id || return

    # Attempt to bind via driverctl
    if ! driverctl set-override "$GPU_ID" vfio-pci; then
        whiptail --title "Error" --msgbox "driverctl failed for $GPU_ID" 8 50
        return 1
    fi

    # Blacklist based on vendor, same as classic pathway
    case "$GPU_VENDOR_ID" in
        10de) add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist nouveau" ;;
        1002) add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist radeon" ;;
    esac

    apply_kernel_configuration
    echo "PASSTHROUGH_CONFIGURED" >> "$STATE_FILE"

    whiptail --title "Done" --msgbox "Driverctl passthrough configured." 8 50
    ask_for_reboot
}

configure_gpu_passthrough() {
    log_message "GPU Passthrough menu"

    if grep -Fxq "PASSTHROUGH_CONFIGURED" "$STATE_FILE"; then
        whiptail --title "Info" --msgbox "Passthrough already configured.✅" 8 50
        return
    fi

    local method
    method=$(whiptail --title "Passthrough Method" --menu "Choose method:" 12 60 2 \
        1 "Classic" \
        2 "Driverctl" \
        3>&1 1>&2 2>&3) || return

    case "$method" in
        1) classic_passthrough    ;;
        2) driverctl_passthrough ;;
    esac
}

unset_driverctl_override() {
    log_message "Prompting to unset driverctl overrides"

    # Gather current overrides
    local overrides
    overrides=$(driverctl list-override | awk '/vfio-pci/ {print $1}')
    if [[ -z "$overrides" ]]; then
        whiptail --title "No Overrides" --msgbox "No driverctl overrides found." 8 50
        return
    fi

    # Build menu items dynamically
    local menu_items=()
    local i=1
    while IFS= read -r pci; do
        menu_items+=("$i" "$pci")
        ((i++))
    done <<< "$overrides"

    # Let the user pick one override to remove
    local choice
    choice=$(whiptail --title "Unset Override" \
        --menu "Select override to unset:" 15 60 "${#menu_items[@]}" \
        "${menu_items[@]}" 3>&1 1>&2 2>&3) || return

    # Map choice back to PCI address
    local idx=$((choice - 1))
    local pci_to_unset=${menu_items[$((idx*2+1))]}

    log_message "Unsetting override for $pci_to_unset"
    if driverctl unset-override "$pci_to_unset"; then
        whiptail --title "Success" --msgbox "Override for $pci_to_unset removed." 8 60
    else
        whiptail --title "Error" --msgbox "Failed to remove override for $pci_to_unset." 8 60
    fi
}

rollback_gpu_passthrough() {
    log_message "Starting full passthrough rollback"

    if ! grep -Fxq "PASSTHROUGH_CONFIGURED" "$STATE_FILE"; then
        whiptail --title "Nothing to Rollback" --msgbox "No passthrough configuration detected." 8 50
        return
    fi

    # Confirm full rollback
    if ! whiptail --title "Confirm Rollback" --yesno \
         "This will remove all VFIO settings, unblacklist drivers,\nand revert initramfs.\nContinue?" 10 60; then
        return
    fi

    # Optionally remove driverctl overrides
    if whiptail --title "Remove driverctl Overrides?" --yesno \
         "Would you like to unset any driverctl overrides?" 8 60; then
        unset_driverctl_override
    fi

    # Clean blacklist.conf
    sed -i '/blacklist \(nouveau\|nvidia\|radeon\|amdgpu\)/d' /etc/modprobe.d/blacklist.conf

    # Extract and remove vfio.conf lines
    local ids
    ids=$(grep -Po '(?<=ids=)[0-9A-Fa-f:,]+' /etc/modprobe.d/vfio.conf || true)
    [[ -n "$ids" ]] && sed -i "/options vfio-pci ids=$ids/d" /etc/modprobe.d/vfio.conf

    # Update initramfs
    if update-initramfs -u -k all &>/dev/null; then
        log_message "initramfs updated successfully"
    else
        log_message "initramfs update failed"
    fi

    # Clear state flag
    sed -i '/PASSTHROUGH_CONFIGURED/d' "$STATE_FILE"

    whiptail --title "Rollback Complete" --msgbox "Passthrough settings reverted." 8 60
    ask_for_reboot
}


install_driverctl() {
    log_message "Ensuring driverctl is installed"

    if command -v driverctl &>/dev/null; then
        whiptail --title "Driverctl" --msgbox "driverctl is already installed." 8 60
        return
    fi

    progress "Installing driverctl..."
    if apt-get update -qq && apt-get install -y driverctl &>/dev/null; then
        whiptail --title "Success" --msgbox "driverctl installed successfully." 8 60
        log_message "driverctl installation succeeded"
    else
        whiptail --title "Error" --msgbox "Failed to install driverctl." 8 60
        log_message "driverctl installation failed"
    fi
}

advanced_kernel_tweaks_menu() {
    while true; do
        local k=$(whiptail --title "⚠ Advanced Kernel Tweaks ⚠" \
            --menu "WARNING: These kernel parameters are EXPERIMENTAL and may cause system instability or boot issues.\n\nProceed only if you fully understand the risks.\n\nSelect a parameter to apply:" \
            20 80 4 \
            1 "pcie_acs_override=downstream,multifunction  [⚠ EXPERIMENTAL]" \
            2 "video=efifb:off  [Disable EFI Framebuffer]" \
            3 "Return to Main Menu" 3>&1 1>&2 2>&3)

        case $k in
            1) 
                whiptail --title "⚠ WARNING ⚠" --msgbox "\
You have selected an EXPERIMENTAL parameter:\n\n\
'pcie_acs_override=downstream,multifunction'\n\n\
This may cause system instability, incorrect IOMMU grouping, or boot failures.\n\
Apply this ONLY if you know what you're doing.\n\n\
Press OK to proceed." 15 70
                append_kernel_param "pcie_acs_override=downstream,multifunction" 
                ;;
            2) 
                append_kernel_param "video=efifb:off" 
                ;;
            3) 
                break 
                ;;
        esac
    done
}



# New test


show_help() {
    whiptail --title "$APP_ID — Help / Credits" --msgbox "\
$APP_NAME ($APP_ID)

Author  : $AUTHOR
Version : $BUILD_DATE
License : MIT

GitHub  : https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility

Sponsors:
  • BuyMeACoffee: $BMAC_URL
  • Patreon     : $PATRON_URL
" 15 70
    pause
}


sponsor_info() {
    whiptail --title "$APP_ID — Sponsorship" --msgbox "\
This tool is created and maintained by:

  $AUTHOR

If you find PECU useful, please consider supporting:

  • BuyMeACoffee : $BMAC_URL
  • Patreon      : $PATRON_URL

Thank you for your support!
" 15 70
    pause
}



# ──────────────────────────────────────────────────────────────
# Main Menu
# ──────────────────────────────────────────────────────────────
main() {
    initialize_state
    show_loading_banner

    # Dynamic terminal size adjustment
    local cols=$(tput cols 2>/dev/null || echo 80)
    local lines=$(tput lines 2>/dev/null || echo 24)
    local menu_w=$(( cols > 80 ? 80 : cols - 4 ))
    local menu_h=$(( lines > 20 ? 18 : lines - 4 ))

    while true; do
        choice=$(whiptail \
          --backtitle "$APP_NAME | Author: $AUTHOR | BuyMeACoffee: $BMAC_URL" \
          --title "MAIN MENU" \
          --menu "Please select an option:" \
          "$menu_h" "$menu_w" 8 \
            1 "Install Dependencies" \
            2 "Configure GPU Passthrough" \
            3 "Check GPU Installation" \
            4 "Rollback GPU Passthrough" \
            5 "Advanced Kernel Tweaks [⚠ EXPERIMENTAL]" \
            6 "Help / Credits" \
            7 "Sponsorship" \
            8 "Exit" \
          3>&1 1>&2 2>&3) || choice=8

        case "$choice" in
            1) initialize_state             ;;
            2) configure_gpu_passthrough    ;;
            3) check_gpu_installation       ;;
            4) rollback_gpu_passthrough     ;;
            5) advanced_kernel_tweaks_menu  ;;
            6) show_help                    ;;
            7) sponsor_info                 ;;
            8)
                if whiptail --title "$APP_ID" --yesno "Are you sure you want to exit?" 8 50; then
                    break
                fi
                ;;
        esac
    done

    show_loading_banner
    echo -e "${GREEN}Thank you for using $APP_ID!${NC}"
}

# Launch the menu
main
exit 0
