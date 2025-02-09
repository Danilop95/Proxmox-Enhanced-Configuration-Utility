#!/bin/bash

# Colors
RED='\e[0;31m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
YELLOW='\e[0;33m'
NC='\e[0m' # No color

# Define backup directory path and state file
BACKUP_DIR="/root/backup-script"
STATE_FILE="$BACKUP_DIR/script_state.txt"

# Change ownership and permissions of the backup directory
sudo chown -R user:user "$BACKUP_DIR"
sudo chmod -R 755 "$BACKUP_DIR"

# Create the backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR" || { echo -e "${RED}Error: Failed to create backup directory.${NC}"; exit 1; }

# Create the state file if it doesn't exist
touch "$STATE_FILE" || { echo -e "${RED}Error: Failed to create state file.${NC}"; exit 1; }

#  Initialize the state file
initialize_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "INITIALIZED" > "$STATE_FILE"
    fi
}

# Check if the user is root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root.${NC}"
    exit 1
fi

#  Detect GPUs and check installation
check_gpu_installation() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Checking GPU Installation                     |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # List GPUs and check for NVIDIA, AMD, Intel iGPU, or AMD APU
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

#  Check Intel iGPU details and status
check_intel_gpu() {
    echo -e "${BLUE}Checking Intel iGPU status...${NC}"
    # Aquí puedes añadir comandos específicos para comprobar el estado de iGPUs Intel
    intel_gpu_info=$(lspci | grep -i 'vga\|3d\|2d' | grep -i 'intel')
    echo "$intel_gpu_info"
}


#  Check NVIDIA GPU details and status
check_nvidia_gpu() {
    if command -v nvidia-smi &> /dev/null; then
        echo -e "${BLUE}nvidia-smi found. Checking NVIDIA GPU status...${NC}"
        nvidia_smi_output=$(nvidia-smi)
        echo "$nvidia_smi_output"
        
        # Check for Data Center or Gaming GPU
        if echo "$nvidia_smi_output" | grep -iq 'Tesla\|A100\|V100\|A30\|A40'; then
            echo -e "${GREEN}Detected NVIDIA Data Center GPU.${NC}"
        else
            echo -e "${GREEN}Detected NVIDIA Gaming GPU.${NC}"
        fi
    else
        echo -e "${RED}nvidia-smi not found. Please install NVIDIA drivers.${NC}"
    fi
}

#  Check AMD GPU details and status
check_amd_gpu() {
    echo -e "${BLUE}Listing AMD GPUs...${NC}"
    amd_gpu_info=$(lshw -C display | grep -i 'amd')
    echo "$amd_gpu_info"

    if command -v rocm-smi &> /dev/null; then
        echo -e "${BLUE}rocm-smi found. Checking AMD GPU status...${NC}"
        rocm_smi_output=$(rocm-smi)
        echo "$rocm_smi_output"

        # Check for Data Center or Gaming GPU
        if echo "$rocm_smi_output" | grep -iq 'Instinct\|MI50\|MI100\|MI200'; then
            echo -e "${GREEN}Detected AMD Data Center GPU.${NC}"
        else
            echo -e "${GREEN}Detected AMD Gaming GPU.${NC}"
        fi
    else
        echo -e "${RED}rocm-smi not found. Please install AMD ROCm drivers.${NC}"
    fi
}

#  Create a backup of the file only if not already done
backup_file() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Creating a backup of sources.list |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "BACKUP_CREATED" "$STATE_FILE"; then
        echo -e "${YELLOW}Backup already created. Skipping...${NC}"
        return 0
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        echo -e "${GREEN}Backup directory created at $BACKUP_DIR.${NC}"
    fi

    backup_files=("${BACKUP_DIR}/sources.list.bak_"*)
    if [[ ${#backup_files[@]} -ge 5 ]]; then
        echo -e "${BLUE}The maximum number of backups has been reached. Delete some backups to make new ones.${NC}"
        return 1
    fi

    backup_filename="${BACKUP_DIR}/sources.list.bak_$(date +%Y%m%d_%H%M%S)"
     cp "/etc/apt/sources.list" "$backup_filename" || { echo -e "${RED}Failed to create backup.${NC}"; exit 1; }
    echo -e "${GREEN}Backup created at $backup_filename.${NC}"

    echo "BACKUP_CREATED" >> "$STATE_FILE"
}

#  Rollback GPU passthrough configuration
rollback_gpu_passthrough() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Rolling Back GPU Passthrough Configuration    |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "PASSTHROUGH_CONFIGURED" "$STATE_FILE"; then
        # Remove passthrough settings
        sed -i '/blacklist nouveau/d' /etc/modprobe.d/blacklist.conf
        sed -i '/blacklist nvidia/d' /etc/modprobe.d/blacklist.conf
        sed -i "/options vfio-pci ids=$(grep 'ids=' /etc/modprobe.d/vfio.conf | awk '{print $3}')/d" /etc/modprobe.d/vfio.conf

        # Update kernel configuration same like POlloLoco Doc "I'm not sure if this is needed, but it doesn't hurt :)"
         update-initramfs -u -k all || { echo -e "${RED}Failed to update initramfs.${NC}"; exit 1; }
        sed -i '/PASSTHROUGH_CONFIGURED/d' "$STATE_FILE"
        echo -e "${GREEN}Rollback completed.${NC}"
    else
        echo -e "${YELLOW}No GPU passthrough configuration found to rollback.${NC}"
    fi

    # Prompt user to reboot
    ask_for_reboot
}

#  Restore a previous backup of the file
restore_backup() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Restoring a previous backup of sources.list |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    backup_files=("${BACKUP_DIR}/sources.list.bak_"*)

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo -e "${RED}No backup files available.${NC}"
        return 1
    fi

    echo -e "${BLUE}Select a backup to restore:${NC}"
    for ((i=0; i<${#backup_files[@]}; i++)); do
        echo -e "${BLUE} $((i+1)))${NC} ${backup_files[$i]}"
    done

    read -p "$(echo -e ${BLUE}Enter the backup number:${NC} )" backup_number

    if ! [[ "$backup_number" =~ ^[1-5]$ ]]; then
        echo -e "${RED}Invalid option.${NC}"
        return 1
    fi

    backup_file="${backup_files[$((backup_number-1))]}"
    if [[ -f "$backup_file" ]]; then
        echo -e "${BLUE}Backup file preview:${NC}"
        echo "-----------------------------------------"
        cat "$backup_file"
        echo "-----------------------------------------"
        echo -n -e "${BLUE}Do you want to restore this backup?${NC} (y/n): "
        read answer
        case $answer in
            [yY])
                 cp "$backup_file" "/etc/apt/sources.list"
                echo -e "${GREEN}Backup restored.${NC}"
                ;;
            *)
                echo -e "${RED}Operation canceled.${NC}"
                ;;
        esac
    else
        echo -e "${RED}The backup file does not exist.${NC}"
    fi
}

#  Open the sources.list file with nano
open_sources_list() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Opening sources.list file with nano         |${NC}"
    echo -e "${BLUE}=================================================${NC}"
     nano "/etc/apt/sources.list"
}

#  Check if a line exists in the sources.list file
line_exists() {
    local line="$1"
    grep -Fxq "$line" "/etc/apt/sources.list"
}

#  Modify the sources.list file if not already modified
modify_sources_list() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Modifying sources.list file                  |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${YELLOW}Adding necessary lines to the sources.list file, if missing.${NC}"

    if grep -Fxq "SOURCES_LIST_MODIFIED" "$STATE_FILE"; then
        echo -e "${YELLOW}sources.list already modified. Skipping...${NC}"
        return 0
    fi

    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://ftp.debian.org/debian bullseye main contrib"
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://ftp.debian.org/debian bullseye-updates main contrib"
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://security.debian.org/debian-security bullseye-security main contrib"
    add_to_file_if_not_exists "/etc/apt/sources.list" "# PVE pve-no-subscription repository provided by proxmox.com, NOT recommended for production use"
    add_to_file_if_not_exists "/etc/apt/sources.list" "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription"

    echo -e "${GREEN}sources.list file modified.${NC}"
    echo "SOURCES_LIST_MODIFIED" >> "$STATE_FILE"
}


#  Add MSI options to the audio configuration file if not already added
add_msi_options() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Adding MSI options for audio                  |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "MSI_OPTIONS_ADDED" "$STATE_FILE"; then
        echo -e "${YELLOW}MSI options already added. Skipping...${NC}"
        return 0
    fi

    add_to_file_if_not_exists "/etc/modprobe.d/snd-hda-intel.conf" "options snd-hda-intel enable_msi=1"
    echo -e "${GREEN}MSI options added.${NC}"
    echo "MSI_OPTIONS_ADDED" >> "$STATE_FILE"
}

# UPDATE REVISION ////////////////////////////////////////////////
# Enable IOMMU (based on Pollo´s doc)

enable_iommu(){
    # Check if IOMMU is already enabled
    if grep -Fxq "IOMMU_ENABLED" "$STATE_FILE"; then
        echo -e "${YELLOW}IOMMU is already enabled. Skipping...${NC}"
        return
    fi

    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Enabling IOMMU (based on POlloLoco's doc)      |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # According to POlloLoco's documentation:
    # 1) You must enable IOMMU in your BIOS/UEFI manually (cannot be automated).
    # 2) Append 'intel_iommu=on' or an equivalent parameter to the kernel.
    # 3) Depending on your setup, you might be using GRUB or systemd-boot.

    # Detect CPU vendor (Intel or AMD)
    local vendor
    vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk -F':' '{print $2}' | xargs)

    # Check which bootloader is in use
    if [[ -f "/etc/default/grub" ]]; then
        echo -e "${BLUE}Detected GRUB...${NC}"
        if [[ "$vendor" == "GenuineIntel" ]]; then
            echo -e "${GREEN}Intel CPU detected. Appending 'intel_iommu=on'...${NC}"
            sed -i 's|\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)|\1 intel_iommu=on|' /etc/default/grub
        else
            echo -e "${GREEN}AMD CPU detected. Using 'iommu=pt' for performance.${NC}"
            sed -i 's|\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)|\1 iommu=pt|' /etc/default/grub
        fi
        update-grub

    elif [[ -f "/etc/kernel/cmdline" ]]; then
        echo -e "${BLUE}Detected systemd-boot...${NC}"
        if [[ "$vendor" == "GenuineIntel" ]]; then
            echo -e "${GREEN}Intel CPU detected. Appending 'intel_iommu=on'...${NC}"
            sed -i 's|$| intel_iommu=on|' /etc/kernel/cmdline
        else
            echo -e "${GREEN}AMD CPU detected. Appending 'iommu=pt' for performance.${NC}"
            sed -i 's|$| iommu=pt|' /etc/kernel/cmdline
        fi
        proxmox-boot-tool refresh

    else
        echo -e "${RED}Could not detect GRUB or systemd-boot. Please enable IOMMU manually.${NC}"
        return
    fi

    # Mark IOMMU as enabled in the state file
    echo "IOMMU_ENABLED" >> "$STATE_FILE"
    echo -e "${GREEN}IOMMU configuration appended. A reboot is required for changes to take effect.${NC}"
}

#  Check if IOMMU is enabled
check_iommu() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Checking if IOMMU is enabled                  |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    dmesg | grep -e DMAR -e IOMMU
}

#  Apply kernel configuration if not already applied
apply_kernel_configuration() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Applying kernel configuration                 |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "KERNEL_CONFIG_APPLIED" "$STATE_FILE"; then
        echo -e "${YELLOW}Kernel configuration already applied. Skipping...${NC}"
        return 0
    fi

    update-initramfs -u -k all
    echo -e "${GREEN}Kernel configuration applied.${NC}"
    echo "KERNEL_CONFIG_APPLIED" >> "$STATE_FILE"
}

# Ask if the user wants to restart
ask_for_reboot() {
    echo -e "${BLUE}=================================================${NC}"
    echo -n -e "${BLUE}Do you want to restart now?${NC} (y/n): "
    read answer
    case $answer in
        [yY])
            echo -e "${BLUE}Restarting the system...${NC}"
            reboot
            ;;
        *)
            echo -e "${BLUE}Please remember to restart the system manually.${NC}"
            ;;
    esac
}

# Add an entry to a file if it doesn't exist
add_to_file_if_not_exists() {
    local file="$1"
    local entry="$2"
    if ! grep -Fxq "$entry" "$file"; then
        echo "$entry" |  tee -a "$file"
    fi
}

# Search for GPU devices
search_gpu_device() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}|        Available Graphics Devices             |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    
    # List all available graphics devices
    lspci | grep -i 'vga\|3d\|2d'
    
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}Please enter the name of the device you are searching for (e.g., GTX 1080):${NC}"
    read device
    lspci -v | grep -i "$device"
}

#  Read the GPU ID
read_gpu_id() {
    echo -e "${BLUE}Enter the ID of the video device (format xx:xx.x):${NC}"
    read GPU_ID
    echo -e "${BLUE}Getting the ID of your GPU:${NC}"
    GPU_VENDOR_ID=$(lspci -n -s "$GPU_ID" | awk '{print $3}')
    echo $GPU_VENDOR_ID
}

#  Configure GPU passthrough
configure_gpu_passthrough() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}|        GPU Passthrough Configuration           |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    if grep -Fxq "PASSTHROUGH_CONFIGURED" "$STATE_FILE"; then
        echo -e "${YELLOW}GPU passthrough already configured. Skipping...${NC}"
        return 0
    fi

    search_gpu_device
    read_gpu_id

    add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist nouveau"
    add_to_file_if_not_exists "/etc/modprobe.d/blacklist.conf" "blacklist nvidia"

    add_to_file_if_not_exists "/etc/modprobe.d/vfio.conf" "options vfio-pci ids=$GPU_VENDOR_ID disable_vga=1"

    apply_kernel_configuration

    echo "PASSTHROUGH_CONFIGURED" >> "$STATE_FILE"

    ask_for_reboot

    echo -e "${BLUE}Press any key to return to the main menu...${NC}"
    read -n 1 -s
}

# Main function of the script
main() {
    initialize_state

    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${BLUE}|              Options Menu                      |${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${BLUE} 1) Install Dependencies${NC}"
        echo -e "${BLUE} 2) Configure GPU Passthrough${NC}"
        echo -e "${BLUE} 3) Check GPU Installation${NC}"
        echo -e "${BLUE} 4) Rollback GPU Passthrough Configuration${NC}"
        echo -e "${BLUE} 5) Exit${NC}"
        echo -e "${BLUE}=================================================${NC}"
        read -p "$(echo -e ${BLUE}Select an option:${NC} )" option

        case $option in
            1)
                while true; do
                    clear
                    echo -e "${BLUE}=================================================${NC}"
                    echo -e "${BLUE}|     Options Menu (Install Dependencies)       |${NC}"
                    echo -e "${BLUE}=================================================${NC}"
                    echo -e "${BLUE} 1) Create a backup of sources.list${NC}"
                    echo -e "${BLUE} 2) Restore a previous backup of sources.list${NC}"
                    echo -e "${BLUE} 3) Modify sources.list file${NC}"
                    echo -e "${BLUE} 4) Open sources.list with nano${NC}"
                    echo -e "${BLUE} 5) Back to main menu${NC}"
                    echo -e "${BLUE}=================================================${NC}"
                    read -p "$(echo -e ${BLUE}Select an option:${NC} )" option_deps

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
                exit
                ;;
            *)
                echo -e "${RED}Invalid option.${NC}"
                ;;
        esac
    done
}

# Execute the script
main
