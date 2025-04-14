#!/bin/bash
# ---------------------------------------------------------
# PROXMOX ENHANCED CONFIG UTILITY (PECU)
# By Daniel Puente García (Danielop95/DVNILXP)
# Version: 2.0
# Date: 12/4/2025
# Description: This script assists in configuring and managing GPU passthrough on Proxmox systems,
#              including advanced kernel tweaks and AMD detection.
# ---------------------------------------------------------

# Colors for output
RED='\e[0;31m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
YELLOW='\e[0;33m'
NC='\e[0m' # No Color

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
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Checking GPU Installation                     |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    local gpu_info
    gpu_info=$(lspci | grep -i 'vga\|3d\|2d')

    if echo "$gpu_info" | grep -iq 'nvidia'; then
        echo -e "${GREEN}NVIDIA GPU detected.${NC}"
        check_nvidia_gpu
    elif echo "$gpu_info" | grep -iq 'amd'; then
        echo -e "${GREEN}AMD GPU detected.${NC}"
        check_amd_gpu
    elif echo "$gpu_info" | grep -iq 'intel'; then
        echo -e "${GREEN}Intel iGPU detected.${NC}"
        check_intel_gpu
    else
        echo -e "${RED}No NVIDIA, AMD, or Intel GPU detected.${NC}"
        echo -e "${BLUE}Press any key to return to the main menu...${NC}"
        read -n 1 -s
        return
    fi

    echo -e "${BLUE}Press any key to return to the main menu...${NC}"
    read -n 1 -s
}

check_intel_gpu() {
    log_message "Checking Intel iGPU status..."
    echo -e "${BLUE}Checking Intel iGPU status...${NC}"
    local intel_gpu_info
    intel_gpu_info=$(lspci | grep -i 'vga\|3d\|2d' | grep -i 'intel')
    echo "$intel_gpu_info"
}

check_nvidia_gpu() {
    log_message "Checking NVIDIA GPU status..."
    if command -v nvidia-smi &> /dev/null; then
        echo -e "${BLUE}nvidia-smi found. Checking NVIDIA GPU status...${NC}"
        local nvidia_smi_output
        nvidia_smi_output=$(nvidia-smi)
        echo "$nvidia_smi_output"
        
        if echo "$nvidia_smi_output" | grep -iq 'Tesla\|A100\|V100\|A30\|A40'; then
            echo -e "${GREEN}Detected NVIDIA Data Center GPU.${NC}"
        else
            echo -e "${GREEN}Detected NVIDIA Gaming GPU.${NC}"
        fi
    else
        echo -e "${RED}nvidia-smi not found. Please install NVIDIA drivers.${NC}"
    fi
}

check_amd_gpu() {
    log_message "Checking AMD GPU status..."
    echo -e "${BLUE}Listing AMD GPUs...${NC}"
    local amd_gpu_info
    amd_gpu_info=$(lshw -C display | grep -i 'amd')
    echo "$amd_gpu_info"

    if command -v rocm-smi &> /dev/null; then
        echo -e "${BLUE}rocm-smi found. Checking AMD GPU status...${NC}"
        local rocm_smi_output
        rocm_smi_output=$(rocm-smi)
        echo "$rocm_smi_output"

        if echo "$rocm_smi_output" | grep -iq 'Instinct\|MI50\|MI100\|MI200'; then
            echo -e "${GREEN}Detected AMD Data Center GPU.${NC}"
        else
            echo -e "${GREEN}Detected AMD Gaming GPU.${NC}"
        fi
    else
        echo -e "${RED}rocm-smi not found. Please install AMD ROCm drivers.${NC}"
    fi
}

# -------------------------------------------------------------
# Backup / Restore functions for sources.list
# -------------------------------------------------------------
backup_file() {
    log_message "Creating a backup of sources.list"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Creating a backup of sources.list             |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "BACKUP_CREATED" "$STATE_FILE"; then
        echo -e "${YELLOW}A backup has already been created. Skipping...${NC}"
        log_message "Backup already created, skipping."
        return
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        echo -e "${GREEN}Backup directory created at $BACKUP_DIR.${NC}"
        log_message "Backup directory created at $BACKUP_DIR."
    fi

    local backup_files
    backup_files=("${BACKUP_DIR}/sources.list.bak_"*)
    if [[ ${#backup_files[@]} -ge 5 ]]; then
        echo -e "${BLUE}The maximum number of backups (5) has been reached.${NC}"
        echo -e "${BLUE}Please remove some old backups before creating a new one.${NC}"
        log_message "Reached max number of backups, skipping creation."
        return 1
    fi

    local backup_filename="${BACKUP_DIR}/sources.list.bak_$(date +%Y%m%d_%H%M%S)"
    cp "/etc/apt/sources.list" "$backup_filename" || {
        echo -e "${RED}Failed to create backup.${NC}"
        log_message "Failed to create backup. Exiting."
        exit 1
    }

    echo -e "${GREEN}Backup created successfully at: $backup_filename.${NC}"
    log_message "Backup created at $backup_filename."
    echo "BACKUP_CREATED" >> "$STATE_FILE"
}

restore_backup() {
    log_message "Restoring a previous backup of sources.list"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Restoring a previous backup of sources.list   |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    local backup_files
    backup_files=("${BACKUP_DIR}/sources.list.bak_"*)

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo -e "${RED}No backup files available to restore.${NC}"
        log_message "No backup files found. Cannot restore."
        return 1
    fi

    echo -e "${BLUE}Select one of the following backups to restore:${NC}"
    for ((i=0; i<${#backup_files[@]}; i++)); do
        echo -e "${BLUE}$((i+1)))${NC} ${backup_files[$i]}"
    done

    echo -ne "${BLUE}Enter the backup number [1-${#backup_files[@]}]: ${NC}"
    read backup_number

    if ! [[ "$backup_number" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid input. Please enter a number only.${NC}"
        log_message "Invalid input for backup number."
        return 1
    fi
    if (( backup_number < 1 || backup_number > ${#backup_files[@]} )); then
        echo -e "${RED}Invalid selection. Please choose a valid backup number.${NC}"
        log_message "User selected an invalid backup number."
        return 1
    fi

    local chosen_backup="${backup_files[$((backup_number-1))]}"
    if [[ -f "$chosen_backup" ]]; then
        echo -e "${BLUE}Preview of $chosen_backup:${NC}"
        echo "-----------------------------------------"
        cat "$chosen_backup"
        echo "-----------------------------------------"

        echo -ne "${BLUE}Restore this backup? (y/n): ${NC}"
        read answer
        case "$answer" in
            [yY])
                cp "$chosen_backup" "/etc/apt/sources.list"
                echo -e "${GREEN}Backup has been successfully restored.${NC}"
                log_message "Restored backup from $chosen_backup."
                ;;
            *)
                echo -e "${RED}Restore operation canceled.${NC}"
                log_message "Restore canceled by user."
                ;;
        esac
    else
        echo -e "${RED}The selected backup file does not exist.${NC}"
        log_message "Backup file does not exist: $chosen_backup."
    fi
}

open_sources_list() {
    log_message "User opening /etc/apt/sources.list with nano."
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Opening sources.list file with nano           |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    nano "/etc/apt/sources.list"
}

line_exists() {
    local line="$1"
    grep -Fxq "$line" "/etc/apt/sources.list"
}

modify_sources_list() {
    log_message "Modifying sources.list with recommended lines..."
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Modifying sources.list file                  |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${YELLOW}Adding necessary lines to sources.list if they are missing.${NC}"

    if grep -Fxq "SOURCES_LIST_MODIFIED" "$STATE_FILE"; then
        echo -e "${YELLOW}sources.list is already modified. Skipping...${NC}"
        log_message "sources.list already modified previously. Skipping."
        return
    fi

    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://ftp.debian.org/debian bullseye main contrib"
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://ftp.debian.org/debian bullseye-updates main contrib"
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://security.debian.org/debian-security bullseye-security main contrib"
    add_to_file_if_not_exists "/etc/apt/sources.list" "# PVE pve-no-subscription repository provided by proxmox.com, NOT recommended for production use"
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription"

    echo -e "${GREEN}sources.list has been successfully updated.${NC}"
    log_message "sources.list updated with recommended lines."
    echo "SOURCES_LIST_MODIFIED" >> "$STATE_FILE"
}

# -------------------------------------------------------------
# MSI, IOMMU, and other Advanced Kernel Settings
# -------------------------------------------------------------
add_msi_options() {
    log_message "Adding MSI options for audio..."
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Adding MSI options for audio                  |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "MSI_OPTIONS_ADDED" "$STATE_FILE"; then
        echo -e "${YELLOW}MSI options have already been added. Skipping...${NC}"
        log_message "MSI options already added, skipping."
        return
    fi

    add_to_file_if_not_exists "/etc/modprobe.d/snd-hda-intel.conf" "options snd-hda-intel enable_msi=1"
    echo -e "${GREEN}MSI options for audio have been successfully added.${NC}"
    log_message "MSI options appended to snd-hda-intel.conf."

    echo "MSI_OPTIONS_ADDED" >> "$STATE_FILE"
}

enable_iommu() {
    log_message "Enabling IOMMU..."
    if grep -Fxq "IOMMU_ENABLED" "$STATE_FILE"; then
        echo -e "${YELLOW}IOMMU is already enabled. Skipping...${NC}"
        log_message "IOMMU already enabled, skipping."
        return
    fi

    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Enabling IOMMU (based on PolloLoco's documentation) |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    local vendor
    vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk -F':' '{print $2}' | xargs)

    if [[ -f "/etc/default/grub" ]]; then
        log_message "Detected GRUB bootloader..."
        echo -e "${BLUE}Detected GRUB as bootloader...${NC}"

        if [[ "$vendor" == "GenuineIntel" ]]; then
            echo -e "${GREEN}Intel CPU detected. Appending 'intel_iommu=on'...${NC}"
            log_message "Appending intel_iommu=on to GRUB_CMDLINE_LINUX_DEFAULT"
            sed -i 's|\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)|\1 intel_iommu=on|' /etc/default/grub
        else
            echo -e "${GREEN}AMD CPU detected. Using 'iommu=pt' for better performance.${NC}"
            log_message "Appending iommu=pt to GRUB_CMDLINE_LINUX_DEFAULT"
            sed -i 's|\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*)|\1 iommu=pt|' /etc/default/grub
        fi

        if command -v update-grub &> /dev/null; then
            update-grub
            log_message "update-grub executed successfully."
        else
            echo -e "${RED}Warning: 'update-grub' command not found. Please update GRUB manually.${NC}"
            log_message "Could not run update-grub, command not found."
        fi

    elif [[ -f "/etc/kernel/cmdline" ]]; then
        log_message "Detected systemd-boot environment..."
        echo -e "${BLUE}Detected systemd-boot (Proxmox-boot-tool)...${NC}"

        if [[ "$vendor" == "GenuineIntel" ]]; then
            echo -e "${GREEN}Intel CPU detected. Appending 'intel_iommu=on'...${NC}"
            sed -i 's|$| intel_iommu=on|' /etc/kernel/cmdline
        else
            echo -e "${GREEN}AMD CPU detected. Appending 'iommu=pt' for better performance.${NC}"
            sed -i 's|$| iommu=pt|' /etc/kernel/cmdline
        fi

        if command -v proxmox-boot-tool &> /dev/null; then
            proxmox-boot-tool refresh
            log_message "proxmox-boot-tool refresh executed."
        else
            echo -e "${RED}Warning: 'proxmox-boot-tool' command not found. Please refresh systemd-boot manually.${NC}"
            log_message "Could not run proxmox-boot-tool refresh."
        fi
    else
        echo -e "${RED}Could not detect GRUB or systemd-boot. Please enable IOMMU manually.${NC}"
        log_message "Failed to detect bootloader for IOMMU."
        return
    fi

    echo "IOMMU_ENABLED" >> "$STATE_FILE"
    echo -e "${GREEN}IOMMU parameters have been appended. A reboot is required for changes to take effect.${NC}"
    log_message "IOMMU enabled. Marked in state file."
}

check_iommu() {
    log_message "Checking if IOMMU is enabled"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Checking if IOMMU is enabled                  |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    dmesg | grep -e DMAR -e IOMMU
}

apply_kernel_configuration() {
    log_message "Applying kernel configuration..."
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Applying kernel configuration                 |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "KERNEL_CONFIG_APPLIED" "$STATE_FILE"; then
        echo -e "${YELLOW}Kernel configuration already applied once. Skipping...${NC}"
        log_message "Kernel config was already applied, skipping."
        return
    fi

    if ! command -v update-initramfs &> /dev/null; then
        echo -e "${RED}Warning: 'update-initramfs' command not found. Please update initramfs manually.${NC}"
        log_message "update-initramfs missing, user must do it manually."
    else
        update-initramfs -u -k all
        echo -e "${GREEN}Kernel configuration applied (initramfs updated).${NC}"
        log_message "initramfs updated successfully."
    fi

    echo "KERNEL_CONFIG_APPLIED" >> "$STATE_FILE"
}

ask_for_reboot() {
    log_message "Prompting user for reboot..."
    echo -e "${BLUE}=================================================${NC}"
    echo -ne "${BLUE}Do you want to restart now? (y/n): ${NC}"
    read answer
    case $answer in
        [yY])
            log_message "User chose to reboot the system..."
            echo -e "${BLUE}Restarting the system...${NC}"
            reboot
            ;;
        *)
            echo -e "${BLUE}Please remember to restart the system manually later if required.${NC}"
            log_message "User postponed reboot."
            ;;
    esac
}

# -------------------------------------------------------------
# Helper Function: Append an Entry to a File Only if It Does Not Already Exist
# -------------------------------------------------------------
add_to_file_if_not_exists() {
    local file="$1"
    local entry="$2"

    if ! grep -Fxq "$entry" "$file"; then
        echo "$entry" | tee -a "$file"
        log_message "Added line '$entry' to $file"
    fi
}

# -------------------------------------------------------------
# Display and Search GPU Devices by Keyword
# -------------------------------------------------------------
search_gpu_device() {
    log_message "Searching GPU device by user input..."
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}|        Available Graphics Devices             |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    lspci | grep -i 'vga\|3d\|2d'

    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}Please enter the name of the device you are searching for (e.g., GTX 1080):${NC}"
    read device

    echo -e "${BLUE}Searching for '$device' in PCI devices...${NC}"
    log_message "User searching for device: $device"
    lspci -v | grep -i "$device"
}

# -------------------------------------------------------------
# Prompt User for GPU ID (xx:xx.x) and Retrieve Vendor/Device ID
# -------------------------------------------------------------
read_gpu_id() {
    log_message "Prompting user for GPU ID..."
    echo -e "${BLUE}Enter the GPU device ID (format xx:xx.x):${NC}"
    read GPU_ID

    if ! [[ "$GPU_ID" =~ ^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}\.[0-9A-Fa-f]$ ]]; then
        echo -e "${RED}Invalid format. Please use the format xx:xx.x (e.g., 01:00.0).${NC}"
        log_message "Invalid GPU ID format: $GPU_ID"
        return 1
    fi

    echo -e "${BLUE}Retrieving Vendor/Device ID for: $GPU_ID${NC}"
    log_message "Retrieving vendor/device ID for $GPU_ID"
    GPU_VENDOR_ID=$(lspci -n -s "$GPU_ID" | awk '{print $3}')

    if [[ -z "$GPU_VENDOR_ID" ]]; then
        echo -e "${RED}Could not retrieve vendor/device ID. Check your GPU ID input.${NC}"
        log_message "Failed to retrieve vendor/device ID for $GPU_ID"
        return 1
    fi

    echo -e "${GREEN}Detected PCI vendor/device: $GPU_VENDOR_ID${NC}"
    log_message "Detected GPU_VENDOR_ID=$GPU_VENDOR_ID"
}

# -------------------------------------------------------------
# Classic or Driverctl GPU Passthrough Methods
# -------------------------------------------------------------
classic_passthrough() {
    log_message "User selected: Classic GPU Passthrough method"
    echo -e "${YELLOW}Using Classic Method (Manual edit of vfio.conf and blacklists)${NC}"
    
    search_gpu_device
    read_gpu_id || return 1

    if [[ "$GPU_VENDOR_ID" =~ 10de ]]; then
        log_message "NVIDIA GPU detected. Blacklisting nouveau and nvidia..."
        add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist nouveau"
        add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist nvidia"
    elif [[ "$GPU_VENDOR_ID" =~ 1002 ]]; then
        log_message "AMD GPU detected. Blacklisting radeon and amdgpu..."
        add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist radeon"
        add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist amdgpu"
    else
        log_message "GPU vendor not recognized for automatic blacklisting."
    fi

    add_to_file_if_not_exists "/etc/modprobe.d/vfio.conf" "options vfio-pci ids=$GPU_VENDOR_ID disable_vga=1"

    apply_kernel_configuration
    echo "PASSTHROUGH_CONFIGURED" >> "$STATE_FILE"
    ask_for_reboot
}

driverctl_passthrough() {
    log_message "User selected: Driverctl GPU Passthrough method"
    echo -e "${YELLOW}Using Driverctl Method (Automatic Persistent Override)${NC}"
    
    install_driverctl

    echo -e "${BLUE}Would you like to select a GPU manually (M) or skip listing (S)?${NC}"
    echo -ne "[M/S]: "
    read user_choice

    local pci_id
    if [[ "$user_choice" =~ ^[Mm]$ ]]; then
        search_gpu_device
        echo -e "${BLUE}Enter the PCI address (e.g., 0000:01:00.0) you want to override:${NC}"
        read pci_id
        log_message "User manually selected PCI address: $pci_id"
    else
        echo -e "${BLUE}Skipping listing. Please enter the PCI address directly (e.g., 0000:01:00.0):${NC}"
        read pci_id
        log_message "User skipped listing. Entered PCI address: $pci_id"
    fi

    echo -e "${YELLOW}Binding $pci_id to vfio-pci via driverctl...${NC}"
    log_message "Attempting 'driverctl set-override $pci_id vfio-pci'..."
    driverctl set-override "$pci_id" vfio-pci || {
        echo -e "${RED}Error: Failed to set driver override via driverctl.${NC}"
        log_message "Failed to override driver for $pci_id"
        return 1
    }

    echo -e "${BLUE}Current driver assignments (overrides):${NC}"
    driverctl list-overrides | tee -a "$LOG_FILE"

    if lspci -n -s "$pci_id" | grep -qi '10de'; then
        echo -e "${GREEN}Detected NVIDIA GPU. Blacklisting nouveau and nvidia...${NC}"
        log_message "Blacklisting nouveau and nvidia for $pci_id"
        add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist nouveau"
        add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist nvidia"
    elif lspci -n -s "$pci_id" | grep -qi '1002'; then
        echo -e "${GREEN}Detected AMD GPU. Blacklisting radeon and amdgpu...${NC}"
        log_message "Blacklisting radeon and amdgpu for $pci_id"
        add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist radeon"
        add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist amdgpu"
    fi

    apply_kernel_configuration
    echo "PASSTHROUGH_CONFIGURED" >> "$STATE_FILE"
    ask_for_reboot
}

# -------------------------------------------------------------
# GPU Passthrough Configuration Menu
# -------------------------------------------------------------
configure_gpu_passthrough() {
    log_message "User entered GPU Passthrough configuration menu."
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}|    GPU Passthrough Configuration Options      |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "PASSTHROUGH_CONFIGURED" "$STATE_FILE"; then
        echo -e "${YELLOW}GPU passthrough already configured. Skipping...${NC}"
        log_message "PASSTHROUGH_CONFIGURED found in $STATE_FILE. Skipping."
        return
    fi

    echo -e "${BLUE}Please select a method for GPU passthrough:${NC}"
    echo -e "${BLUE} 1) Classic (edit vfio.conf and blacklists)${NC}"
    echo -e "${BLUE} 2) Driverctl (automatic persistent override)${NC}"
    echo -e "${BLUE}-------------------------------------------------${NC}"

    echo -e "${YELLOW}Choose a passthrough method (1 or 2):${NC}"
    read method

    case $method in
        1)
            classic_passthrough
            ;;
        2)
            driverctl_passthrough
            ;;
        *)
            echo -e "${RED}Invalid option. Returning to main menu...${NC}"
            log_message "Invalid passthrough method selected."
            sleep 2
            ;;
    esac
}

# -------------------------------------------------------------
# Unset Driverctl Override Hook
# -------------------------------------------------------------
unset_driverctl_override() {
    echo -e "${BLUE}Enter the PCI address you want to unset (e.g., 0000:01:00.0):${NC}"
    read pci_unset

    if driverctl list-overrides | grep -q "$pci_unset"; then
        log_message "Unsetting driverctl override for $pci_unset"
        driverctl unset-override "$pci_unset"
        echo -e "${GREEN}Driverctl override for $pci_unset has been removed.${NC}"
    else
        echo -e "${RED}No override found for $pci_unset.${NC}"
        log_message "No override found for $pci_unset. Skipping."
    fi
}

# -------------------------------------------------------------
# Rollback GPU Passthrough Configuration
# -------------------------------------------------------------
rollback_gpu_passthrough() {
    log_message "User selected: Rollback GPU passthrough"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Rolling Back GPU Passthrough Configuration    |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "PASSTHROUGH_CONFIGURED" "$STATE_FILE"; then
        echo -e "${BLUE}Would you like to unset any existing driverctl overrides? (y/n)${NC}"
        read ans
        if [[ "$ans" =~ ^[yY]$ ]]; then
            unset_driverctl_override
        fi

        log_message "Removing lines from blacklist.conf and vfio.conf..."
        sed -i '/blacklist nouveau/d' /etc/modprobe.d/blacklist.conf
        sed -i '/blacklist nvidia/d' /etc/modprobe.d/blacklist.conf
        sed -i '/blacklist radeon/d' /etc/modprobe.d/blacklist.conf
        sed -i '/blacklist amdgpu/d' /etc/modprobe.d/blacklist.conf

        gpu_ids=$(grep 'ids=' /etc/modprobe.d/vfio.conf | awk '{print $3}' | sed 's/ids=//; s/disable_vga.*//')
        if [[ -n "$gpu_ids" ]]; then
            sed -i "/options vfio-pci ids=$gpu_ids/d" /etc/modprobe.d/vfio.conf
        fi

        if command -v update-initramfs &> /dev/null; then
            update-initramfs -u -k all
        else
            echo -e "${YELLOW}update-initramfs not found. Skipping initramfs update...${NC}"
            log_message "Skipping initramfs update because it's not found."
        fi

        sed -i '/PASSTHROUGH_CONFIGURED/d' "$STATE_FILE"
        echo -e "${GREEN}Rollback completed.${NC}"
        log_message "GPU passthrough rollback completed."
    else
        echo -e "${YELLOW}No GPU passthrough configuration found to rollback.${NC}"
        log_message "No existing passthrough config found."
    fi

    ask_for_reboot
}

# -------------------------------------------------------------
# Driverctl Installer
# -------------------------------------------------------------
install_driverctl() {
    log_message "Checking/Installing driverctl..."
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Checking and Installing driverctl             |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if ! command -v driverctl &> /dev/null; then
        echo -e "${GREEN}driverctl not found. Installing now...${NC}"
        log_message "Installing driverctl package..."
        apt-get update && apt-get install -y driverctl || {
            echo -e "${RED}Error: Failed to install driverctl.${NC}"
            log_message "Error installing driverctl."
            return 1
        }
        echo -e "${GREEN}driverctl installed successfully.${NC}"
        log_message "driverctl installed."
    else
        echo -e "${YELLOW}driverctl is already installed. Skipping...${NC}"
        log_message "driverctl already installed."
    fi
    sleep 2
}

# -------------------------------------------------------------
# Loading Screen (Banner and Spinner)
# -------------------------------------------------------------
show_loading_banner() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}  PROXMOX ENHANCED CONFIG UTILITY (PECU)        ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}      By Daniel Puente García (Danielop95/DVNILXP)${NC}"
    echo

    local banner_lines=(
"    ____  ______________  __"
"   / __ \\/ ____/ ____/ / / /"
"  / /_/ / __/ / /   / / / / "
" / ____/ /___/ /___/ /_/ /  "
"/_/   /_____/\____/\____/   "
"                            "
    )

    echo -e "${YELLOW}"
    for line in "${banner_lines[@]}"; do
        echo "$line"
        sleep 0.07
    done
    echo -e "${NC}"
    sleep 0.5
}

show_technologies_and_spinner() {
    local techs=(
        "Intel"
        "Intel | AMD"
        "Intel | AMD | Nvidia"
        "Intel | AMD | Nvidia | Proxmox"
        "Intel | AMD | Nvidia | Proxmox | Debian"
    )

    echo -ne "${YELLOW}Supported Technologies: ${NC}"
    for t in "${techs[@]}"; do
        printf "\r${YELLOW}Supported Technologies: %s${NC}" "$t"
        sleep 0.7
    done
    echo
    sleep 1
}

# -------------------------------------------------------------
# Advanced Kernel Tweaks Sub-menu
# -------------------------------------------------------------
advanced_kernel_tweaks_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${BLUE}|    Advanced Kernel Tweaks Menu                |${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${BLUE} 1) Enable pcie_acs_override=downstream,multifunction${NC}"
        echo -e "${BLUE} 2) Disable efifb (video=efifb:off)              ${NC}"
        echo -e "${BLUE} 3) Return to main menu                         ${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -ne "${BLUE}Select an option: ${NC}"
        read tweak_opt

        case $tweak_opt in
            1)
                append_kernel_param "pcie_acs_override=downstream,multifunction"
                ;;
            2)
                append_kernel_param "video=efifb:off"
                ;;
            3)
                break
                ;;
            *)
                echo -e "${RED}Invalid option.${NC}"
                sleep 1
                ;;
        esac
    done
}

append_kernel_param() {
    local param="$1"
    if [[ -f "/etc/default/grub" ]]; then
        echo -e "${YELLOW}Appending '$param' to GRUB_CMDLINE_LINUX_DEFAULT...${NC}"
        log_message "Appending '$param' to GRUB_CMDLINE_LINUX_DEFAULT"
        sed -i "s|\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)|\1 $param|" /etc/default/grub
        if command -v update-grub &> /dev/null; then
            update-grub
        fi
        echo -e "${GREEN}Appended $param to GRUB cmdline and updated GRUB.${NC}"
        ask_for_reboot
    elif [[ -f "/etc/kernel/cmdline" ]]; then
        echo -e "${YELLOW}Appending '$param' to /etc/kernel/cmdline...${NC}"
        log_message "Appending '$param' to /etc/kernel/cmdline"
        sed -i "s|\$| $param|" /etc/kernel/cmdline
        if command -v proxmox-boot-tool &> /dev/null; then
            proxmox-boot-tool refresh
        fi
        echo -e "${GREEN}Appended $param to /etc/kernel/cmdline and refreshed systemd-boot.${NC}"
        ask_for_reboot
    else
        echo -e "${RED}Could not detect GRUB or systemd-boot. Cannot append kernel parameter automatically.${NC}"
        log_message "Failed to detect bootloader for kernel parameter $param"
    fi
}

# -------------------------------------------------------------
# Main menu
# -------------------------------------------------------------
main() {
    initialize_state

    # Loading screen
    show_loading_banner
    show_technologies_and_spinner

    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${BLUE}|              Options Menu                      |${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${BLUE} 1) Install Dependencies${NC}"
        echo -e "${BLUE} 2) Configure GPU Passthrough${NC}"
        echo -e "${BLUE} 3) Check GPU Installation${NC}"
        echo -e "${BLUE} 4) Rollback GPU Passthrough Configuration${NC}"
        echo -e "${BLUE} 5) Advanced Kernel Tweaks${NC}"
        echo -e "${BLUE} 6) Exit${NC}"
        echo -e "${BLUE}=================================================${NC}"

        echo -ne "${BLUE}Select an option:${NC} "
        read option
        case $option in
            1)
                while true; do
                    clear
                    echo -e "${BLUE}=================================================${NC}"
                    echo -e "${BLUE}|     Options Menu \(Install Dependencies)       |${NC}"
                    echo -e "${BLUE}=================================================${NC}"
                    echo -e "${BLUE} 1) Create a backup of sources.list${NC}"
                    echo -e "${BLUE} 2) Restore a previous backup of sources.list${NC}"
                    echo -e "${BLUE} 3) Modify sources.list file${NC}"
                    echo -e "${BLUE} 4) Open sources.list with nano${NC}"
                    echo -e "${BLUE} 5) Back to main menu${NC}"
                    echo -e "${BLUE} 6) Install driverctl \(recommended for PCIe passthrough)${NC}"
                    echo -e "${BLUE}=================================================${NC}"

                    echo -ne "${BLUE}Select an option:${NC} "
                    read option_deps
                    case $option_deps in
                        1)
                            backup_file
                            sleep 2
                            ;;
                        2)
                            restore_backup
                            sleep 2
                            ;;
                        3)
                            modify_sources_list
                            sleep 2
                            ;;
                        4)
                            open_sources_list
                            sleep 2
                            ;;
                        5)
                            break
                            ;;
                        6)
                            install_driverctl
                            ;;
                        *)
                            echo -e "${RED}Invalid option.${NC}"
                            sleep 2
                            ;;
                    esac
                done
                ;;
            2)
                configure_gpu_passthrough
                ;;
            3)
                check_gpu_installation
                ;;
            4)
                rollback_gpu_passthrough
                ;;
            5)
                advanced_kernel_tweaks_menu
                ;;
            6)
                log_message "User chose to exit PECU. Goodbye!"
                exit
                ;;
            *)
                echo -e "${RED}Invalid option.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Ejecutamos el script
main

