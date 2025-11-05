#!/bin/bash
################################################################################
#                                                                              #
#                 ██████╗ ███████╗ ██████╗██╗   ██╗                           #
#                 ██╔══██╗██╔════╝██╔════╝██║   ██║                           #
#                 ██████╔╝█████╗  ██║     ██║   ██║                           #
#                 ██╔═══╝ ██╔══╝  ██║     ██║   ██║                           #
#                 ██║     ███████╗╚██████╗╚██████╔╝                           #
#                 ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝                            #
#                                                                              #
#              PROXMOX ENHANCED CONFIGURATION UTILITY (PECU)                  #
#                  GPU Passthrough Configuration Suite                        #
#                                                                              #
################################################################################
#                                                                              #
#  Author:        Daniel Puente García                                        #
#  GitHub:        @Danilop95                                                  #
#  Version:       3.1                                                          #
#  Release Date:  November 4, 2025                                            #
#                                                                              #
#  ──────────────────────────────────────────────────────────────────────────  #
#                                                                              #
#  💖 Support this project:                                                   #
#     • Buy Me a Coffee: https://buymeacoffee.com/danilop95                   #
#     • Official Website: https://pecu.tools                                  #
#                                                                              #
#  ──────────────────────────────────────────────────────────────────────────  #
#                                                                              #
#  Description:                                                                #
#    Complete GPU passthrough configuration utility for Proxmox VE            #
#    • Supports NVIDIA, AMD, Intel GPUs (including datacenter cards)          #
#    • Automated IOMMU detection and configuration                            #
#    • VFIO module setup and management                                       #
#    • Intelligent GPU driver blacklisting                                    #
#    • VM template creation and management                                    #
#    • Bootloader detection (systemd-boot/GRUB)                               #
#    • Idempotent repository management                                       #
#    • Live configuration verification                                        #
#                                                                              #
#  Supported Systems:                                                          #
#    • Proxmox VE 7.x (Debian 11 - Bullseye)                                  #
#    • Proxmox VE 8.x (Debian 12 - Bookworm)                                  #
#    • Proxmox VE 9.x (Debian 13 - Trixie)                                    #
#                                                                              #
#  License:       MIT License                                                  #
#  Repository:    github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility #
#                                                                              #
################################################################################

# Colors for output
RED='\e[0;31m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
YELLOW='\e[0;33m'
CYAN='\e[0;36m'
PURPLE='\e[0;35m'
NC='\e[0m' # No Color

# Application metadata
APP_ID="PECU"
APP_NAME="Proxmox-Enhanced-Configuration-Utility"
AUTHOR="Daniel Puente García"
VERSION="3.1"
BUILD_DATE="2025-11-04"
BMAC_URL="https://buymeacoffee.com/danilop95"
WEBSITE_URL="https://pecu.tools"

# Configuration constants
VFIO_MODULES=("vfio" "vfio_pci" "vfio_iommu_type1")
NVIDIA_MODULES=("nouveau" "nvidia" "nvidiafb")
AMD_MODULES=("amdgpu" "radeon")
INTEL_MODULES=("i915")



# Global configuration directories and files
BACKUP_DIR="/root/pecu-backup"
STATE_FILE="$BACKUP_DIR/pecu_state.conf"
LOG_FILE="/var/log/pecu.log"
CONFIG_DIR="/etc/pecu"
VFIO_CONFIG="/etc/modprobe.d/vfio.conf"
BLACKLIST_CONFIG="/etc/modprobe.d/blacklist-gpu.conf"
KVM_CONFIG="/etc/modprobe.d/kvm.conf"

# Detection flags
declare -A DETECTED_GPUS
declare -A GPU_IOMMU_GROUPS
declare -A GPU_DEVICE_IDS

# System information
CPU_VENDOR=""
BOOT_TYPE=""
IOMMU_STATUS=""

# Create necessary directories
create_directories() {
    local dirs=("$BACKUP_DIR" "$CONFIG_DIR")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || {
                log_error "Failed to create directory: $dir"
                exit 1
            }
            chown root:root "$dir"
            chmod 755 "$dir"
        fi
    done
    
    # Create state file if it doesn't exist
    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << EOF
# PECU Configuration State File
# Generated on $(date)
INITIALIZED=true
IOMMU_CONFIGURED=false
VFIO_CONFIGURED=false
GPU_BLACKLISTED=false
PASSTHROUGH_READY=false
EOF
    fi
}

# Cleanup function for temporary files and processes
cleanup_on_exit() {
    local exit_code=$?
    
    # Clean up temporary files
    find /tmp -name "pecu_*" -type f -mtime +1 2>/dev/null | xargs rm -f
    
    # Clean up temporary vendor-reset directory if it exists
    [[ -d "/tmp/vendor-reset" ]] && rm -rf "/tmp/vendor-reset"
    
    # Log exit
    if [[ $exit_code -eq 0 ]]; then
        log_info "PECU exited successfully"
    else
        log_error "PECU exited with error code $exit_code"
    fi
    
    exit $exit_code
}

# Set up cleanup trap
trap cleanup_on_exit EXIT INT TERM

# Enhanced logging system
log_message() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local color=""
    
    case "$level" in
        "ERROR")   color="$RED" ;;
        "WARNING") color="$YELLOW" ;;
        "SUCCESS") color="$GREEN" ;;
        "INFO")    color="$BLUE" ;;
        "DEBUG")   color="$CYAN" ;;
        *)         color="$NC" ;;
    esac
    
    # Check log file permissions before writing
    if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
        echo -e "${RED}Warning: Cannot write to log directory $(dirname "$LOG_FILE")${NC}" >&2
        echo -e "${color}[$timestamp] [$level] $message${NC}"
        return 1
    fi
    
    if [[ -f "$LOG_FILE" ]] && [[ ! -w "$LOG_FILE" ]]; then
        echo -e "${RED}Warning: Cannot write to log file $LOG_FILE${NC}" >&2
        echo -e "${color}[$timestamp] [$level] $message${NC}"
        return 1
    fi
    
    # Rotate log file if it gets too large (> 10MB)
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        echo "[$timestamp] [INFO] Log file rotated" > "$LOG_FILE"
    fi
    
    echo -e "${color}[$timestamp] [$level] $message${NC}" | tee -a "$LOG_FILE"
}

log_info() { log_message "INFO" "$1"; }
log_error() { log_message "ERROR" "$1"; }
log_warning() { log_message "WARNING" "$1"; }
log_success() { log_message "SUCCESS" "$1"; }
log_debug() { log_message "DEBUG" "$1"; }


# ---------------------------------------------------------
# System Detection and Validation Functions
# ---------------------------------------------------------

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root.${NC}"
        echo -e "${YELLOW}Please run with 'sudo' or as root user.${NC}"
        exit 1
    fi
}

# Check system dependencies
check_deps() {
    local missing=()
    for bin in whiptail lspci qm pveversion awk sed grep find dmesg; do
        command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
    done
    if (( ${#missing[@]} )); then
        log_error "Missing dependencies: ${missing[*]}"
        echo -e "${RED}Error: Missing required commands: ${missing[*]}${NC}"
        echo -e "${YELLOW}Please install missing packages and run again.${NC}"
        exit 1
    fi
}

# Detect system information
detect_system_info() {
    log_info "Detecting system information..."
    
    # Detect CPU vendor
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        CPU_VENDOR="intel"
        log_info "Detected Intel CPU"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        CPU_VENDOR="amd"
        log_info "Detected AMD CPU"
    else
        log_warning "Unknown CPU vendor detected"
        CPU_VENDOR="unknown"
    fi
    
    # Detect boot type using robust detection
    BOOT_TYPE=$(detect_bootloader)
    case "$BOOT_TYPE" in
        "systemd-boot") log_info "Detected UEFI with systemd-boot" ;;
        "grub-uefi") log_info "Detected UEFI with GRUB" ;;
        "grub-legacy") log_info "Detected Legacy BIOS with GRUB" ;;
        *) log_warning "Unknown boot type: $BOOT_TYPE" ;;
    esac
    
    # Check IOMMU status - improved detection
    if dmesg | grep -qE "IOMMU|DMAR|AMD-Vi" && [[ -d "/sys/kernel/iommu_groups" ]]; then
        IOMMU_STATUS="enabled"
        log_success "IOMMU is enabled and active"
    elif dmesg | grep -qE "IOMMU|DMAR|AMD-Vi"; then
        IOMMU_STATUS="detected"
        log_warning "IOMMU detected but may not be fully active"
    else
        IOMMU_STATUS="disabled"
        log_warning "IOMMU is not enabled"
    fi
}

# ---------------------------------------------------------
# Bootloader Detection and Module Validation
# ---------------------------------------------------------

# Robust bootloader detection for systemd-boot vs GRUB
detect_bootloader() {
    local boot_type="unknown"
    
    # Check for UEFI
    if [[ -d "/sys/firmware/efi" ]]; then
        # Check for systemd-boot (Proxmox 7+)
        # Multiple indicators for robust detection
        if command -v pve-efiboot-tool >/dev/null 2>&1 || command -v proxmox-boot-tool >/dev/null 2>&1; then
            # Verify cmdline file exists
            if [[ -f "/etc/kernel/cmdline" ]]; then
                boot_type="systemd-boot"
            elif [[ -d "/etc/kernel" ]]; then
                # Directory exists but no cmdline file - create it
                log_warning "systemd-boot detected but /etc/kernel/cmdline missing - creating"
                mkdir -p /etc/kernel
                # Copy current cmdline as base
                cat /proc/cmdline > /etc/kernel/cmdline 2>/dev/null || echo "root=ZFS=rpool/ROOT/pve-1 boot=zfs" > /etc/kernel/cmdline
                boot_type="systemd-boot"
            else
                log_warning "systemd-boot tools found but /etc/kernel missing"
                boot_type="grub-uefi"
            fi
        else
            boot_type="grub-uefi"
        fi
    else
        boot_type="grub-legacy"
    fi
    
    echo "$boot_type"
}

# Validate and ensure kernel module exists before loading
# Args: module_name
# Returns: 0 if valid, 1 if invalid
ensure_module() {
    local module="$1"
    
    if [[ -z "$module" ]]; then
        log_error "ensure_module: No module name provided"
        return 1
    fi
    
    # Test if module can be loaded (dry-run)
    if modprobe -n "$module" >/dev/null 2>&1; then
        log_debug "Module '$module' validation passed"
        return 0
    else
        log_error "Module '$module' does not exist or cannot be loaded"
        return 1
    fi
}

# Add module to modules-load.d if valid and not already present (idempotent)
# Args: module_name, config_file
add_module_persistent() {
    local module="$1"
    local config_file="${2:-/etc/modules-load.d/vfio.conf}"
    
    # Validate module exists
    if ! ensure_module "$module"; then
        log_error "Cannot add invalid module '$module' to $config_file"
        return 1
    fi
    
    # Check if already present
    if [[ -f "$config_file" ]] && grep -q "^${module}$" "$config_file"; then
        log_debug "Module '$module' already in $config_file"
        return 0
    fi
    
    # Add module
    echo "$module" >> "$config_file"
    log_success "Added module '$module' to $config_file"
    
    # Try to load it now
    if ! lsmod | grep -q "^${module}"; then
        if modprobe "$module" 2>/dev/null; then
            log_success "Loaded module '$module'"
        else
            log_warning "Module '$module' added to config but failed to load immediately"
        fi
    fi
    
    return 0
}

# ---------------------------------------------------------
# Hardware Requirements and Detection
# ---------------------------------------------------------

check_hardware_requirements() {
    log_info "Checking hardware requirements for GPU passthrough..."
    local requirements_met=true
    
    # Check if running on Proxmox VE
    if ! command -v pveversion >/dev/null 2>&1; then
        log_error "This script is designed for Proxmox VE systems"
        requirements_met=false
    else
        local pve_version=$(pveversion | head -1)
        log_info "Running on: $pve_version"
    fi
    
    # Check virtualization support
    if ! grep -qE "vmx|svm" /proc/cpuinfo; then
        log_error "CPU does not support virtualization (VT-x/AMD-V)"
        requirements_met=false
    else
        log_success "CPU virtualization support detected"
    fi
    
    # Check IOMMU support in CPU
    case "$CPU_VENDOR" in
        "intel")
            if dmesg | grep -qE "Intel-IOMMU|DMAR"; then
                log_success "Intel VT-d support detected"
            else
                log_warning "Intel VT-d may not be enabled in BIOS"
            fi
            ;;
        "amd")
            if dmesg | grep -qE "AMD-Vi|IOMMU"; then
                log_success "AMD-Vi support detected"
            else
                log_warning "AMD-Vi may not be enabled in BIOS"
            fi
            ;;
    esac
    
    # Check for GPUs
    if ! lspci | grep -qE "VGA|3D|Display"; then
        log_error "No GPU devices found"
        requirements_met=false
    else
        log_success "GPU devices detected"
    fi
    
    if ! $requirements_met; then
        whiptail --title "Hardware Requirements" --msgbox \
            "Hardware requirements not met. Check the log for details." 10 60
        return 1
    fi
    
    whiptail --title "Hardware Check" --msgbox \
        "Hardware requirements check completed successfully!" 8 60
    return 0
}

# Detect and catalog all GPUs
detect_gpus() {
    log_info "Scanning for GPU devices..."
    
    # Clear previous detection
    DETECTED_GPUS=()
    GPU_IOMMU_GROUPS=()
    GPU_DEVICE_IDS=()
    
    local gpu_count=0
    local gpu_info=""
    
    # Get all GPU devices
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local pci_id=$(echo "$line" | awk '{print $1}')
            # Fix: Don't add 0000: prefix if already present
            local full_id="$pci_id"
            if [[ ! "$pci_id" =~ ^[0-9a-fA-F]{4}: ]]; then
                full_id="0000:$pci_id"
            fi
            local description=$(echo "$line" | cut -d' ' -f2-)
            
            # Get vendor:device ID
            local vendor_device=$(lspci -n -s "$pci_id" | awk '{print $3}')
            
            # Get IOMMU group if available
            local iommu_group=""
            if [[ -d "/sys/kernel/iommu_groups" ]]; then
                local iommu_link=$(find /sys/kernel/iommu_groups -name "*$pci_id*" 2>/dev/null)
                if [[ -n "$iommu_link" ]]; then
                    iommu_group=$(echo "$iommu_link" | grep -o 'iommu_groups/[0-9]*' | cut -d'/' -f2)
                fi
            fi
            
            # Store GPU information
            DETECTED_GPUS["$gpu_count"]="$full_id|$description|$vendor_device"
            GPU_IOMMU_GROUPS["$gpu_count"]="$iommu_group"
            GPU_DEVICE_IDS["$gpu_count"]="$vendor_device"
            
            gpu_info+="GPU $gpu_count: $pci_id - $description\n"
            gpu_info+="  Vendor:Device: $vendor_device\n"
            [[ -n "$iommu_group" ]] && gpu_info+="  IOMMU Group: $iommu_group\n"
            gpu_info+="\n"
            
            ((gpu_count++))
        fi
    done < <(lspci | grep -E "VGA|3D|Display")
    
    if [[ $gpu_count -eq 0 ]]; then
        whiptail --title "GPU Detection" --msgbox "No GPU devices found!" 8 50
        return 1
    fi
    
    log_success "Detected $gpu_count GPU device(s)"
    
    # Display results
    whiptail --title "Detected GPUs" --msgbox \
        "Found $gpu_count GPU device(s):\n\n$gpu_info" 20 80
    
    return 0
}

# Check IOMMU groups and isolation
check_iommu_groups() {
    log_info "Analyzing IOMMU groups..."
    
    if [[ ! -d "/sys/kernel/iommu_groups" ]]; then
        whiptail --title "IOMMU Groups" --msgbox \
            "IOMMU is not active. Please enable IOMMU first." 8 60
        return 1
    fi
    
    local groups_info=""
    local problematic_groups=""
    
    # Analyze each IOMMU group
    for group_path in /sys/kernel/iommu_groups/*/; do
        if [[ -d "$group_path" ]]; then
            local group_num=$(basename "$group_path")
            local device_count=0
            local group_devices=""
            
            for device in "$group_path/devices/"*; do
                if [[ -e "$device" ]]; then
                    local pci_id=$(basename "$device")
                    local device_info=$(lspci -s "$pci_id")
                    group_devices+="    $device_info\n"
                    ((device_count++))
                fi
            done
            
            groups_info+="Group $group_num ($device_count devices):\n$group_devices\n"
            
            # Check if group has GPU and other devices
            if echo "$group_devices" | grep -qE "VGA|3D|Display" && [[ $device_count -gt 1 ]]; then
                if ! echo "$group_devices" | grep -q "Audio"; then
                    problematic_groups+="Group $group_num has GPU mixed with other devices\n"
                fi
            fi
        fi
    done
    
    # Show results
    if [[ -n "$problematic_groups" ]]; then
        whiptail --title "IOMMU Analysis" --yesno \
            "WARNING: Some GPUs are not properly isolated:\n\n$problematic_groups\nThis may require ACS override.\n\nContinue anyway?" 15 70
        return $?
    else
        whiptail --title "IOMMU Groups" --msgbox \
            "IOMMU Groups:\n\n$groups_info\nGPU isolation looks good!" 20 80
    fi
    
    return 0
}

# ---------------------------------------------------------
# IOMMU Configuration Functions
# ---------------------------------------------------------

# Configure IOMMU in kernel parameters
configure_iommu() {
    log_info "Configuring IOMMU for $CPU_VENDOR CPU..."
    
    local iommu_params=""
    case "$CPU_VENDOR" in
        "intel") iommu_params="intel_iommu=on iommu=pt" ;;
        "amd")   iommu_params="amd_iommu=on iommu=pt" ;;
        *)       log_error "Unknown CPU vendor: $CPU_VENDOR"; return 1 ;;
    esac
    
    case "$BOOT_TYPE" in
        "systemd-boot")
            configure_systemd_boot_iommu "$iommu_params"
            ;;
        "grub-uefi"|"grub-legacy")
            configure_grub_iommu "$iommu_params"
            ;;
        *)
            log_error "Unknown boot type: $BOOT_TYPE"
            return 1
            ;;
    esac
    
    # Update state
    sed -i 's/IOMMU_CONFIGURED=false/IOMMU_CONFIGURED=true/' "$STATE_FILE"
    log_success "IOMMU configuration completed"
    
    return 0
}

# Configure GRUB for IOMMU
configure_grub_iommu() {
    local params="$1"
    log_info "Configuring GRUB with IOMMU parameters: $params"
    
    if [[ ! -f "/etc/default/grub" ]]; then
        log_error "GRUB configuration file not found"
        return 1
    fi
    
    # Backup GRUB config
    cp /etc/default/grub "$BACKUP_DIR/grub.bak.$(date +%Y%m%d_%H%M%S)"
    
    # Check if parameters already exist
    if grep -qF "$params" /etc/default/grub; then
        log_warning "IOMMU parameters already present in GRUB"
        return 0
    fi
    
    # Add parameters - improved regex to handle quotes properly
    sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\([^\"]*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $params\"/" /etc/default/grub
    
    # Update GRUB
    if update-grub 2>/dev/null; then
        log_success "GRUB updated successfully"
    else
        log_error "Failed to update GRUB"
        return 1
    fi
    
    return 0
}

# Configure systemd-boot for IOMMU
configure_systemd_boot_iommu() {
    local params="$1"
    log_info "Configuring systemd-boot with IOMMU parameters: $params"
    
    local cmdline_file="/etc/kernel/cmdline"
    
    # Ensure cmdline file exists
    if [[ ! -f "$cmdline_file" ]]; then
        log_warning "systemd-boot cmdline file not found at $cmdline_file"
        
        # Try to create it from current boot
        if [[ -f "/proc/cmdline" ]]; then
            log_info "Creating $cmdline_file from current /proc/cmdline"
            mkdir -p /etc/kernel
            cat /proc/cmdline > "$cmdline_file"
        else
            log_error "Cannot create cmdline file - /proc/cmdline not available"
            return 1
        fi
    fi
    
    # Backup cmdline
    cp "$cmdline_file" "$BACKUP_DIR/cmdline.bak.$(date +%Y%m%d_%H%M%S)"
    
    # Check if parameters already exist (word boundary check)
    local param_check
    local already_present=true
    for param in $params; do
        local param_base="${param%%=*}"
        if ! grep -qE "(^| )${param_base}(=| |$)" "$cmdline_file"; then
            already_present=false
            break
        fi
    done
    
    if $already_present; then
        log_warning "IOMMU parameters already present in cmdline"
        return 0
    fi
    
    # Add parameters (idempotent - only add if not present)
    local current_cmdline=$(cat "$cmdline_file")
    echo "$current_cmdline $params" | sed 's/  */ /g; s/^ //; s/ $//' > "$cmdline_file"
    
    log_info "Updated $cmdline_file"
    
    # Refresh boot entries - try both tool names (proxmox-boot-tool is newer)
    local refresh_success=false
    if command -v proxmox-boot-tool >/dev/null 2>&1; then
        log_info "Running proxmox-boot-tool refresh..."
        if proxmox-boot-tool refresh 2>&1 | tee -a "$LOG_FILE"; then
            refresh_success=true
            log_success "systemd-boot updated with proxmox-boot-tool"
        else
            log_warning "proxmox-boot-tool refresh failed, trying reinit..."
            if proxmox-boot-tool reinit 2>&1 | tee -a "$LOG_FILE"; then
                log_info "Reinit successful, running refresh again..."
                if proxmox-boot-tool refresh 2>&1 | tee -a "$LOG_FILE"; then
                    refresh_success=true
                    log_success "systemd-boot updated after reinit"
                fi
            fi
        fi
    elif command -v pve-efiboot-tool >/dev/null 2>&1; then
        log_info "Running pve-efiboot-tool refresh..."
        if pve-efiboot-tool refresh 2>&1 | tee -a "$LOG_FILE"; then
            refresh_success=true
            log_success "systemd-boot updated with pve-efiboot-tool"
        fi
    else
        log_error "No systemd-boot tool found (proxmox-boot-tool or pve-efiboot-tool)"
        return 1
    fi
    
    if ! $refresh_success; then
        log_error "Failed to update systemd-boot - cmdline file updated but boot entries may be stale"
        whiptail --title "Boot Update Warning" --msgbox \
            "Kernel parameters were written to $cmdline_file\nbut boot entry refresh failed.\n\nYou may need to run manually:\nproxmox-boot-tool refresh\n\nOr check if ESP is mounted correctly." 12 60
        return 1
    fi
    
    return 0
}

# Add additional kernel parameters
add_kernel_parameter() {
    local param="$1"
    local description="$2"
    
    log_info "Adding kernel parameter: $param ($description)"
    
    case "$BOOT_TYPE" in
        "systemd-boot")
            local cmdline_file="/etc/kernel/cmdline"
            
            if [[ ! -f "$cmdline_file" ]]; then
                log_error "Cmdline file not found: $cmdline_file"
                return 1
            fi
            
            # Check for parameter (handle = in parameters correctly)
            local param_base="${param%%=*}"
            if grep -qE "(^| )${param_base}(=| |$)" "$cmdline_file"; then
                log_warning "Parameter $param_base already exists in cmdline"
                return 0
            fi
            
            # Backup
            cp "$cmdline_file" "$BACKUP_DIR/cmdline.param.$(date +%Y%m%d_%H%M%S)"
            
            # Add parameter
            local current_cmdline=$(cat "$cmdline_file")
            echo "$current_cmdline $param" | sed 's/  */ /g; s/^ //; s/ $//' > "$cmdline_file"
            
            # Refresh with proper tool
            local refresh_tool=""
            if command -v proxmox-boot-tool >/dev/null 2>&1; then
                refresh_tool="proxmox-boot-tool"
            elif command -v pve-efiboot-tool >/dev/null 2>&1; then
                refresh_tool="pve-efiboot-tool"
            else
                log_error "No systemd-boot refresh tool available"
                return 1
            fi
            
            if $refresh_tool refresh 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Added $param to systemd-boot"
            else
                log_error "Failed to refresh EFI boot"
                # Try reinit and refresh for proxmox-boot-tool
                if [[ "$refresh_tool" == "proxmox-boot-tool" ]]; then
                    log_info "Attempting reinit then refresh..."
                    if proxmox-boot-tool reinit && proxmox-boot-tool refresh; then
                        log_success "Added $param after reinit"
                        return 0
                    fi
                fi
                return 1
            fi
            ;;
        "grub-uefi"|"grub-legacy")
            local grub_file="/etc/default/grub"
            
            if [[ ! -f "$grub_file" ]]; then
                log_error "GRUB config file not found: $grub_file"
                return 1
            fi
            
            # Backup
            cp "$grub_file" "$BACKUP_DIR/grub.param.$(date +%Y%m%d_%H%M%S)"
            
            # Check if GRUB_CMDLINE_LINUX_DEFAULT exists
            if ! grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file"; then
                echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' >> "$grub_file"
            fi
            
            # Check for parameter
            local param_base="${param%%=*}"
            if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" | grep -qE "\b${param_base}\b"; then
                log_warning "Parameter $param_base already exists in GRUB config"
                return 0
            fi
            
            # Add parameter safely - handle existing quotes properly
            sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"\([^\"]*\)\"/\"\1 $param\"/" "$grub_file"
            
            if update-grub 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Added $param to GRUB"
            else
                log_error "Failed to update GRUB"
                return 1
            fi
            ;;
    esac
}

# Configure additional kernel parameters menu
configure_additional_parameters() {
    local choice
    choice=$(whiptail --title "Additional Kernel Parameters" --menu \
        "Select additional parameters to configure:" 15 80 7 \
        1 "video=efifb:off (Disable EFI framebuffer)" \
        2 "initcall_blacklist=sysfb_init (Disable system framebuffer)" \
        3 "pcie_acs_override=downstream (Override IOMMU groups - RISKY)" \
        4 "vfio-pci.disable_vga=1 (Disable VGA arbitration)" \
        5 "kvm.ignore_msrs=1 (Ignore MSR access)" \
        6 "None - Skip additional parameters" \
        7 "Custom parameter" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) add_kernel_parameter "video=efifb:off" "EFI framebuffer disable" ;;
        2) add_kernel_parameter "initcall_blacklist=sysfb_init" "System framebuffer disable" ;;
        3) 
            if whiptail --title "WARNING" --yesno \
                "pcie_acs_override reduces security by bypassing IOMMU isolation.\nOnly use if your hardware has problematic IOMMU groups.\nContinue?" 10 70; then
                add_kernel_parameter "pcie_acs_override=downstream" "ACS override"
            fi
            ;;
        4) add_kernel_parameter "vfio-pci.disable_vga=1" "VFIO VGA disable" ;;
        5) add_kernel_parameter "kvm.ignore_msrs=1" "KVM MSR ignore" ;;
        6) log_info "Skipping additional parameters" ;;
        7) 
            local custom_param
            custom_param=$(whiptail --inputbox "Enter custom kernel parameter:" 8 60 3>&1 1>&2 2>&3)
            if [[ -n "$custom_param" ]]; then
                add_kernel_parameter "$custom_param" "Custom parameter"
            fi
            ;;
    esac
}

# ---------------------------------------------------------
# VFIO and Module Configuration Functions
# ---------------------------------------------------------

# Configure VFIO modules
configure_vfio_modules() {
    log_info "Configuring VFIO modules..."
    
    local vfio_conf="/etc/modules-load.d/vfio.conf"
    local all_modules_valid=true
    
    # Create header for modules config file
    cat > "$vfio_conf" << EOF
# VFIO modules for GPU passthrough
# Generated by PECU on $(date)
EOF
    
    # Validate and add each module
    log_info "Validating VFIO kernel modules..."
    for module in "${VFIO_MODULES[@]}"; do
        if ! add_module_persistent "$module" "$vfio_conf"; then
            log_error "Failed to validate/add module: $module"
            all_modules_valid=false
        fi
    done
    
    if ! $all_modules_valid; then
        log_error "Some VFIO modules failed validation - check kernel version compatibility"
        whiptail --title "Module Validation Error" --msgbox \
            "Some VFIO modules could not be validated.\n\nThis may indicate:\n- Kernel version mismatch\n- Missing kernel modules\n- Incorrect module names\n\nCheck $LOG_FILE for details." 12 60
        return 1
    fi
    
    # Update state
    sed -i 's/VFIO_CONFIGURED=false/VFIO_CONFIGURED=true/' "$STATE_FILE"
    log_success "VFIO modules configured and validated successfully"
    
    return 0
}

# Blacklist GPU drivers
blacklist_gpu_drivers() {
    log_info "Configuring GPU driver blacklist..."
    
    # Backup existing blacklist
    if [[ -f "/etc/modprobe.d/blacklist.conf" ]]; then
        cp /etc/modprobe.d/blacklist.conf "$BACKUP_DIR/blacklist.conf.bak.$(date +%Y%m%d_%H%M%S)"
    fi
    
    local choice
    choice=$(whiptail --title "GPU Driver Blacklist" --menu \
        "Select which GPU drivers to blacklist:" 15 70 6 \
        1 "NVIDIA drivers (nouveau, nvidia)" \
        2 "AMD drivers (amdgpu, radeon)" \
        3 "Intel drivers (i915)" \
        4 "All GPU drivers" \
        5 "Custom selection" \
        6 "Skip blacklisting" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) blacklist_nvidia_drivers ;;
        2) blacklist_amd_drivers ;;
        3) blacklist_intel_drivers ;;
        4) blacklist_all_drivers ;;
        5) blacklist_custom_drivers ;;
        6) log_info "Skipping driver blacklisting" ;;
        *) return 1 ;;
    esac
    
    # Update initramfs if changes were made
    if [[ "$choice" != "6" ]]; then
        log_info "Updating initramfs..."
        
        # Check if current kernel exists
        local current_kernel=$(uname -r)
        if [[ ! -d "/lib/modules/$current_kernel" ]]; then
            log_warning "Modules directory for current kernel ($current_kernel) not found"
            log_info "Updating for all available kernels..."
        fi
        
        if update-initramfs -u -k all; then
            log_success "initramfs updated successfully"
            sed -i 's/GPU_BLACKLISTED=false/GPU_BLACKLISTED=true/' "$STATE_FILE"
        else
            log_error "Failed to update initramfs"
            whiptail --title "Error" --msgbox \
                "Failed to update initramfs. Check logs for details." 8 50
            return 1
        fi
    fi
    
    return 0
}

# Blacklist NVIDIA drivers
blacklist_nvidia_drivers() {
    log_info "Blacklisting NVIDIA drivers..."
    
    cat > "$BLACKLIST_CONFIG" << EOF
# NVIDIA GPU driver blacklist
# Generated by PECU on $(date)
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
EOF
    
    log_success "NVIDIA drivers blacklisted"
}

# Blacklist AMD drivers
blacklist_amd_drivers() {
    log_info "Blacklisting AMD drivers..."
    
    cat > "$BLACKLIST_CONFIG" << EOF
# AMD GPU driver blacklist
# Generated by PECU on $(date)
blacklist amdgpu
blacklist radeon
EOF
    
    log_success "AMD drivers blacklisted"
}

# Blacklist Intel drivers
blacklist_intel_drivers() {
    log_info "Blacklisting Intel drivers..."
    
    cat > "$BLACKLIST_CONFIG" << EOF
# Intel GPU driver blacklist
# Generated by PECU on $(date)
blacklist i915
EOF
    
    log_success "Intel drivers blacklisted"
}

# Blacklist all GPU drivers
blacklist_all_drivers() {
    log_info "Blacklisting all GPU drivers..."
    
    cat > "$BLACKLIST_CONFIG" << EOF
# All GPU driver blacklist
# Generated by PECU on $(date)
# NVIDIA drivers
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
# AMD drivers
blacklist amdgpu
blacklist radeon
# Intel drivers
blacklist i915
EOF
    
    log_success "All GPU drivers blacklisted"
}

# Custom driver blacklist
blacklist_custom_drivers() {
    local modules
    modules=$(whiptail --inputbox "Enter module names to blacklist (space-separated):" 8 60 3>&1 1>&2 2>&3)
    
    if [[ -n "$modules" ]]; then
        cat > "$BLACKLIST_CONFIG" << EOF
# Custom GPU driver blacklist
# Generated by PECU on $(date)
EOF
        
        for module in $modules; do
            echo "blacklist $module" >> "$BLACKLIST_CONFIG"
        done
        
        log_success "Custom drivers blacklisted: $modules"
    fi
}

# Configure VFIO device IDs
configure_vfio_device_ids() {
    log_info "Configuring VFIO device IDs..."
    
    if [[ ${#DETECTED_GPUS[@]} -eq 0 ]]; then
        log_error "No GPUs detected. Run GPU detection first."
        return 1
    fi
    
    local gpu_list=""
    for i in "${!DETECTED_GPUS[@]}"; do
        local info="${DETECTED_GPUS[$i]}"
        local bdf_full=$(echo "$info" | cut -d'|' -f1)              # 0000:01:00.0
        local desc=$(echo "$info" | cut -d'|' -f2)
        local id=$(echo "$info" | cut -d'|' -f3)
        gpu_list+="$i \"$bdf_full - $desc ($id)\" "
    done
    
    local selected_gpus
    eval "selected_gpus=(\$(whiptail --title \"Select GPUs for VFIO\" --checklist \
        \"Choose GPUs to configure for passthrough:\" 20 80 10 \
        $gpu_list 3>&1 1>&2 2>&3))"
    
    if [[ ${#selected_gpus[@]} -eq 0 ]]; then
        log_warning "No GPUs selected for VFIO configuration"
        return 0
    fi
    
    local device_ids=""
    for idx in "${selected_gpus[@]}"; do
        idx=$(echo "$idx" | tr -d '"')
        local info="${DETECTED_GPUS[$idx]}"
        local bdf_full=$(echo "$info" | cut -d'|' -f1)              # 0000:01:00.0
        local gpu_id=$(echo "$info" | cut -d'|' -f3)

        [[ -n "$device_ids" ]] && device_ids+=","
        device_ids+="$gpu_id"

        # Add companion audio device (function .1) if exists
        local bdf_audio="${bdf_full%.*}.1"
        local audio_id
        audio_id=$(lspci -n -s "$bdf_audio" | awk '{print $3}')
        if [[ -n "$audio_id" ]]; then
            device_ids+=",$audio_id"
        fi
    done

    cat > "$VFIO_CONFIG" << EOF
# VFIO GPU configuration
# Generated by PECU on $(date)
options vfio-pci ids=$device_ids disable_vga=1
EOF

    log_success "VFIO device IDs configured: $device_ids"
    return 0
}

# Configure KVM options
configure_kvm_options() {
    log_info "Configuring KVM options for better GPU compatibility..."
    
    # Create KVM configuration
    cat > "$KVM_CONFIG" << EOF
# KVM configuration for GPU passthrough
# Generated by PECU on $(date)
# Ignore MSR access for better NVIDIA compatibility
options kvm ignore_msrs=1 report_ignored_msrs=0
EOF
    
    # Create separate VFIO IOMMU configuration
    cat > "/etc/modprobe.d/vfio_iommu_type1.conf" << EOF
# VFIO IOMMU Type1 configuration for GPU passthrough
# Generated by PECU on $(date)
# Allow unsafe interrupts if needed
options vfio_iommu_type1 allow_unsafe_interrupts=1
EOF
    
    log_success "KVM and VFIO options configured"
    return 0
}

# ---------------------------------------------------------
# Repository Management Functions (Idempotent)
# ---------------------------------------------------------

# Add a repository line to a file only if not already present (idempotent)
# Args: file_path, repo_line, [description]
# Returns: 0 if added or exists, 1 on error
add_repo_line() {
    local file_path="$1"
    local repo_line="$2"
    local description="${3:-repository entry}"
    
    if [[ -z "$file_path" ]] || [[ -z "$repo_line" ]]; then
        log_error "add_repo_line: file_path and repo_line required"
        return 1
    fi
    
    # Create parent directory if needed
    local dir_path=$(dirname "$file_path")
    if [[ ! -d "$dir_path" ]]; then
        mkdir -p "$dir_path" || {
            log_error "Failed to create directory: $dir_path"
            return 1
        }
    fi
    
    # Create file with header if it doesn't exist
    if [[ ! -f "$file_path" ]]; then
        cat > "$file_path" << EOF
# PECU-MANAGED: APT Repository Configuration
# Managed by Proxmox Enhanced Configuration Utility
# Generated on $(date)
# DO NOT EDIT - Changes may be overwritten by PECU
EOF
        chmod 644 "$file_path"
        log_debug "Created new repo file: $file_path"
    fi
    
    # Check for exact match (using grep -qxF for exact line match)
    if grep -qxF "$repo_line" "$file_path"; then
        log_debug "Repository line already present: $repo_line"
        return 0
    fi
    
    # Check if similar line exists (same URL but different format)
    local repo_url=$(echo "$repo_line" | awk '{print $2}')
    if [[ -n "$repo_url" ]] && grep -qF "$repo_url" "$file_path"; then
        log_warning "Similar repository URL already exists in $file_path: $repo_url"
        log_warning "Existing line differs in format - not adding duplicate"
        return 0
    fi
    
    # Add the line
    echo "$repo_line" >> "$file_path"
    log_success "Added $description: $repo_line"
    
    return 0
}

# Remove PECU-managed repository lines from a file
# Args: file_path
# Returns: 0 on success
remove_pecu_repos() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        log_debug "File does not exist, nothing to remove: $file_path"
        return 0
    fi
    
    # Check if file is PECU-managed
    if ! grep -q "^# PECU-MANAGED:" "$file_path"; then
        log_warning "File is not PECU-managed, skipping: $file_path"
        return 0
    fi
    
    # Backup before removing
    cp "$file_path" "$BACKUP_DIR/$(basename "$file_path").removed.$(date +%Y%m%d_%H%M%S)"
    
    # Remove the file
    rm -f "$file_path"
    log_success "Removed PECU-managed repository file: $file_path"
    
    return 0
}

# Dry-run mode: show what would be added without making changes
# Args: file_path, repo_line, description
show_repo_change() {
    local file_path="$1"
    local repo_line="$2"
    local description="${3:-repository entry}"
    
    if [[ ! -f "$file_path" ]]; then
        echo "  [NEW FILE] $file_path"
        echo "    → $repo_line"
    elif grep -qxF "$repo_line" "$file_path"; then
        echo "  [EXISTS] $description"
        echo "    ✓ $repo_line"
    else
        echo "  [ADD] $description to $file_path"
        echo "    + $repo_line"
    fi
}

# Get Debian codename from Proxmox version
get_debian_codename() {
    local pve_version
    
    # Try to get PVE version
    if command -v pveversion >/dev/null 2>&1; then
        pve_version=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1 2>/dev/null)
    fi
    
    # Map PVE version to Debian codename
    case "$pve_version" in
        7) echo "bullseye" ;;    # Debian 11
        8) echo "bookworm" ;;    # Debian 12
        9) echo "trixie" ;;      # Debian 13
        *)
            # Fallback: detect from /etc/os-release
            if [[ -f /etc/os-release ]]; then
                source /etc/os-release
                echo "${VERSION_CODENAME:-bookworm}"
            else
                echo "bookworm"  # Safe default
            fi
            ;;
    esac
}

# ---------------------------------------------------------
# Advanced Configuration Functions
# ---------------------------------------------------------

# Install vendor-reset for AMD GPUs
install_vendor_reset() {
    log_info "Installing vendor-reset for AMD GPU reset bug fix..."
    
    if ! whiptail --title "Install vendor-reset" --yesno \
        "vendor-reset helps fix AMD GPU reset issues in VMs.\nRequired packages will be installed.\nContinue?" 10 60; then
        return 0
    fi
    
    # Check network connectivity first
    log_info "Checking network connectivity..."
    if ! ping -c 1 github.com >/dev/null 2>&1; then
        log_error "No network connectivity to GitHub"
        whiptail --title "Network Error" --msgbox \
            "Cannot reach GitHub. Please check your internet connection." 8 50
        return 1
    fi
    
    # Check if kernel headers are available
    local kernel_headers="linux-headers-$(uname -r)"
    log_info "Checking kernel headers availability..."
    if ! apt-cache show "$kernel_headers" >/dev/null 2>&1; then
        log_warning "Kernel headers for current kernel may not be available"
        if ! whiptail --title "Kernel Headers" --yesno \
            "Kernel headers for $(uname -r) may not be available.\nThis could cause compilation to fail.\n\nContinue anyway?" 10 60; then
            return 0
        fi
    fi
    
    # Install dependencies
    log_info "Installing build dependencies..."
    if ! apt update; then
        log_error "Failed to update package lists"
        return 1
    fi
    
    if ! apt install -y dkms build-essential git "$kernel_headers"; then
        log_error "Failed to install dependencies"
        return 1
    fi
    
    # Clone and build vendor-reset
    local temp_dir="/tmp/vendor-reset"
    rm -rf "$temp_dir"
    
    log_info "Downloading vendor-reset..."
    if ! git clone https://github.com/gnif/vendor-reset.git "$temp_dir"; then
        log_error "Failed to clone vendor-reset repository"
        return 1
    fi
    
    cd "$temp_dir" || return 1
    
    log_info "Building and installing vendor-reset..."
    if dkms add . && dkms install "vendor-reset/$(cat VERSION)"; then
        echo "vendor-reset" >> /etc/modules
        log_success "vendor-reset installed successfully"
        
        # Cleanup temp directory
        cd - > /dev/null
        rm -rf "$temp_dir"
        
        whiptail --title "vendor-reset" --msgbox \
            "vendor-reset installed successfully!\nIt will be loaded on next reboot." 8 60
        return 0
    else
        log_error "Failed to build/install vendor-reset"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
}

# Configure sources.list for additional packages (idempotent)
configure_sources_list() {
    log_info "Configuring APT sources (idempotent mode)..."
    
    # Get Debian codename
    local debian_codename=$(get_debian_codename)
    local pve_version
    
    if command -v pveversion >/dev/null 2>&1; then
        pve_version=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1 2>/dev/null)
    else
        pve_version="unknown"
    fi
    
    log_info "Detected Proxmox VE $pve_version (Debian $debian_codename)"
    
    # Backup main sources.list if not already backed up recently
    local backup_marker="$BACKUP_DIR/.sources_backed_up_$(date +%Y%m%d)"
    if [[ ! -f "$backup_marker" ]] && [[ -f /etc/apt/sources.list ]]; then
        cp /etc/apt/sources.list "$BACKUP_DIR/sources.list.bak.$(date +%Y%m%d_%H%M%S)"
        touch "$backup_marker"
        log_info "Backed up /etc/apt/sources.list"
    fi
    
    # Define repository configuration
    local pecu_sources_file="/etc/apt/sources.list.d/pecu-repos.list"
    local repos_added=0
    
    # Debian main repositories
    local debian_main="deb http://ftp.debian.org/debian $debian_codename main contrib"
    local debian_updates="deb http://ftp.debian.org/debian $debian_codename-updates main contrib"
    local debian_security=""
    
    # Security repo format differs by version
    case "$debian_codename" in
        bullseye|bookworm)
            debian_security="deb http://security.debian.org/debian-security $debian_codename-security main contrib"
            ;;
        trixie|forky)  # Debian 13+ uses different security format
            debian_security="deb http://security.debian.org/debian-security $debian_codename-security main contrib"
            ;;
        *)
            debian_security="deb http://security.debian.org/debian-security $debian_codename-security main contrib"
            ;;
    esac
    
    log_info "Adding Debian repositories to $pecu_sources_file..."
    
    # Add repositories idempotently
    if add_repo_line "$pecu_sources_file" "$debian_main" "Debian main repository"; then
        ((repos_added++))
    fi
    
    if add_repo_line "$pecu_sources_file" "$debian_updates" "Debian updates repository"; then
        ((repos_added++))
    fi
    
    if add_repo_line "$pecu_sources_file" "$debian_security" "Debian security repository"; then
        ((repos_added++))
    fi
    
    # Proxmox no-subscription repository (optional)
    if whiptail --title "Proxmox Repository" --yesno \
        "Add Proxmox no-subscription repository?\n\nThis provides access to the Proxmox package repository without an enterprise subscription.\n\nRecommended for home labs and testing.\n\nAdd repository?" 12 70; then
        
        local pve_repo="deb http://download.proxmox.com/debian/pve $debian_codename pve-no-subscription"
        
        if add_repo_line "$pecu_sources_file" "$pve_repo" "Proxmox no-subscription repository"; then
            ((repos_added++))
            log_info "Proxmox no-subscription repository added"
        fi
    else
        log_info "Skipping Proxmox no-subscription repository"
    fi
    
    # Summary
    if [[ $repos_added -gt 0 ]]; then
        log_success "Repository configuration complete"
        log_info "Managed file: $pecu_sources_file"
        
        # Update package lists
        if whiptail --title "Update Package Lists" --yesno \
            "Repository configuration updated.\n\nRun 'apt update' now to refresh package lists?" 10 60; then
            
            log_info "Updating APT package lists..."
            if apt update 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Package lists updated successfully"
            else
                log_warning "Some warnings during apt update (this is often normal)"
            fi
        else
            log_info "Skipping apt update - run manually when ready"
        fi
    else
        log_info "All repositories already configured - no changes needed"
    fi
    
    # Show current configuration
    if [[ -f "$pecu_sources_file" ]]; then
        local repo_count=$(grep -c "^deb " "$pecu_sources_file" 2>/dev/null || echo 0)
        log_info "Total repositories in PECU config: $repo_count"
    fi
    
    return 0
}

# Show current repository configuration status
show_repo_status() {
    log_info "Checking current repository configuration..."
    
    local status_report=""
    status_report+="═══════════════════════════════════════════════════════\n"
    status_report+="           REPOSITORY CONFIGURATION STATUS\n"
    status_report+="═══════════════════════════════════════════════════════\n\n"
    
    # System info
    local debian_codename=$(get_debian_codename)
    local pve_version
    if command -v pveversion >/dev/null 2>&1; then
        pve_version=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1 2>/dev/null)
    else
        pve_version="N/A"
    fi
    
    status_report+="System Information:\n"
    status_report+="  Proxmox VE: $pve_version\n"
    status_report+="  Debian Codename: $debian_codename\n\n"
    
    # PECU-managed repositories
    local pecu_sources="/etc/apt/sources.list.d/pecu-repos.list"
    status_report+="PECU-Managed Repositories:\n"
    status_report+="────────────────────────────────────────────────────\n"
    
    if [[ -f "$pecu_sources" ]]; then
        local repo_count=$(grep -c "^deb " "$pecu_sources" 2>/dev/null || echo 0)
        status_report+="  File: $pecu_sources\n"
        status_report+="  Status: ✓ Configured\n"
        status_report+="  Repositories: $repo_count\n\n"
        
        status_report+="  Configured entries:\n"
        while IFS= read -r line; do
            if [[ "$line" =~ ^deb ]]; then
                status_report+="    • $line\n"
            fi
        done < "$pecu_sources"
    else
        status_report+="  Status: ✗ Not configured\n"
        status_report+="  File: $pecu_sources (does not exist)\n"
    fi
    
    status_report+="\n"
    
    # Legacy check - old pve-install.list file
    local old_sources="/etc/apt/sources.list.d/pve-install.list"
    if [[ -f "$old_sources" ]]; then
        status_report+="Legacy Configuration:\n"
        status_report+="────────────────────────────────────────────────────\n"
        status_report+="  ⚠ Old file detected: $old_sources\n"
        status_report+="  This file may contain duplicate entries.\n"
        status_report+="  Consider removing and re-running PECU configuration.\n\n"
    fi
    
    # Check for user-managed repositories
    status_report+="Other Repository Files:\n"
    status_report+="────────────────────────────────────────────────────\n"
    local other_repos=$(find /etc/apt/sources.list.d/ -name "*.list" ! -name "pecu-repos.list" 2>/dev/null | wc -l)
    status_report+="  Count: $other_repos files\n"
    
    if [[ $other_repos -gt 0 ]]; then
        status_report+="  Files:\n"
        find /etc/apt/sources.list.d/ -name "*.list" ! -name "pecu-repos.list" 2>/dev/null | while read -r file; do
            status_report+="    - $(basename "$file")\n"
        done
    fi
    
    status_report+="\n"
    status_report+="Main sources.list:\n"
    status_report+="────────────────────────────────────────────────────\n"
    if [[ -f /etc/apt/sources.list ]]; then
        local main_repo_count=$(grep -c "^deb " /etc/apt/sources.list 2>/dev/null || echo 0)
        status_report+="  Status: ✓ Present\n"
        status_report+="  Repositories: $main_repo_count\n"
    else
        status_report+="  Status: ✗ Missing\n"
    fi
    
    status_report+="\n"
    status_report+="═══════════════════════════════════════════════════════\n"
    
    # Display report
    echo -e "$status_report" | tee -a "$LOG_FILE"
    
    whiptail --title "Repository Status" --scrolltext --msgbox \
        "$status_report" 30 65
    
    return 0
}

# Dry-run preview of repository configuration changes
preview_repo_changes() {
    log_info "Generating repository configuration preview..."
    
    local debian_codename=$(get_debian_codename)
    local pecu_sources_file="/etc/apt/sources.list.d/pecu-repos.list"
    
    local preview=""
    preview+="═══════════════════════════════════════════════════════\n"
    preview+="        REPOSITORY CONFIGURATION PREVIEW\n"
    preview+="                  (DRY-RUN MODE)\n"
    preview+="═══════════════════════════════════════════════════════\n\n"
    
    preview+="Target Debian: $debian_codename\n"
    preview+="Target File: $pecu_sources_file\n\n"
    
    preview+="Planned Changes:\n"
    preview+="────────────────────────────────────────────────────\n"
    
    # Check each repository
    local debian_main="deb http://ftp.debian.org/debian $debian_codename main contrib"
    show_repo_change "$pecu_sources_file" "$debian_main" "Debian main" | while read -r line; do
        preview+="$line\n"
    done
    
    local debian_updates="deb http://ftp.debian.org/debian $debian_codename-updates main contrib"
    show_repo_change "$pecu_sources_file" "$debian_updates" "Debian updates" | while read -r line; do
        preview+="$line\n"
    done
    
    local debian_security="deb http://security.debian.org/debian-security $debian_codename-security main contrib"
    show_repo_change "$pecu_sources_file" "$debian_security" "Debian security" | while read -r line; do
        preview+="$line\n"
    done
    
    local pve_repo="deb http://download.proxmox.com/debian/pve $debian_codename pve-no-subscription"
    show_repo_change "$pecu_sources_file" "$pve_repo" "Proxmox no-subscription" | while read -r line; do
        preview+="$line\n"
    done
    
    preview+="\n"
    preview+="Legend:\n"
    preview+="  [NEW FILE] - File will be created\n"
    preview+="  [ADD]      - Line will be added\n"
    preview+="  [EXISTS]   - Already configured (no change)\n"
    preview+="\n"
    preview+="═══════════════════════════════════════════════════════\n"
    preview+="Note: This is a preview only. No changes will be made.\n"
    preview+="Run 'Configure APT Sources' to apply changes.\n"
    preview+="═══════════════════════════════════════════════════════\n"
    
    echo -e "$preview" | tee -a "$LOG_FILE"
    
    whiptail --title "Repository Preview (Dry-Run)" --scrolltext --msgbox \
        "$preview" 30 65
    
    return 0
}

# Install essential packages
install_dependencies() {
    log_info "Installing essential packages for GPU passthrough..."
    
    local packages=(
        "pciutils"
        "lshw" 
        "dkms"
        "build-essential"
    )
    
    # Add CPU-specific packages
    case "$CPU_VENDOR" in
        "intel") packages+=("intel-microcode") ;;
        "amd") packages+=("amd64-microcode") ;;
    esac
    
    log_info "Installing packages: ${packages[*]}"
    
    if apt update && apt install -y "${packages[@]}"; then
        log_success "Essential packages installed successfully"
    else
        log_error "Failed to install some packages"
        return 1
    fi
    
    return 0
}

# Check current GPU passthrough status
check_passthrough_status() {
    log_info "Checking current GPU passthrough status..."
    
    local status_info=""
    
    # Check IOMMU (more robust check)
    if [[ -d /sys/kernel/iommu_groups ]] && dmesg | grep -qiE "IOMMU|DMAR|AMD-Vi"; then
        local iommu_groups=$(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
        status_info+="+ IOMMU: Enabled ($iommu_groups groups)\n"
    else
        status_info+="- IOMMU: Disabled or incomplete\n"
    fi
    
    # Check VFIO modules
    local vfio_loaded=true
    local vfio_status=""
    for module in "${VFIO_MODULES[@]}"; do
        if lsmod | grep -q "^$module"; then
            vfio_status+="  * $module: loaded\n"
        else
            vfio_status+="  * $module: not loaded\n"
            vfio_loaded=false
        fi
    done
    
    if $vfio_loaded; then
        status_info+="+ VFIO Modules: All loaded\n"
    else
        status_info+="- VFIO Modules: Missing modules\n"
    fi
    status_info+="$vfio_status"
    
    # Check blacklisted drivers
    if [[ -f "$BLACKLIST_CONFIG" ]] && [[ -s "$BLACKLIST_CONFIG" ]]; then
        status_info+="+ GPU Drivers: Blacklisted\n"
    else
        status_info+="- GPU Drivers: Not blacklisted\n"
    fi
    
    # Check VFIO device binding
    if [[ -f "$VFIO_CONFIG" ]] && [[ -s "$VFIO_CONFIG" ]]; then
        status_info+="+ VFIO Devices: Configured\n"
    else
        status_info+="- VFIO Devices: Not configured\n"
    fi
    
    # Check for bound devices
    local bound_devices=$(find /sys/bus/pci/drivers/vfio-pci -name "0000:*" 2>/dev/null | wc -l)
    status_info+="  VFIO-bound devices: $bound_devices\n"
    
    # Check kernel parameters
    local cmdline=""
    case "$BOOT_TYPE" in
        "systemd-boot")
            [[ -f "/etc/kernel/cmdline" ]] && cmdline=$(cat /etc/kernel/cmdline)
            ;;
        "grub-uefi"|"grub-legacy")
            [[ -f "/proc/cmdline" ]] && cmdline=$(cat /proc/cmdline)
            ;;
    esac
    
    if echo "$cmdline" | grep -q "iommu=\|intel_iommu=\|amd_iommu="; then
        status_info+="+ Kernel parameters: Configured\n"
    else
        status_info+="- Kernel parameters: Missing\n"
    fi
    
    whiptail --title "GPU Passthrough Status" --msgbox \
        "Current GPU Passthrough Configuration:\n\n$status_info\nLegend: + = OK, - = Issue" 20 70
    
    return 0
}

# Live verification of applied configuration
# Checks /proc/cmdline, lsmod, and required configuration elements
# Returns non-zero if any required element is missing
verify_configuration_live() {
    log_info "Running live configuration verification..."
    
    local verification_failed=false
    local verification_report=""
    local current_cmdline=$(cat /proc/cmdline 2>/dev/null)
    
    verification_report+="═══════════════════════════════════════════════════════\n"
    verification_report+="           LIVE CONFIGURATION VERIFICATION\n"
    verification_report+="═══════════════════════════════════════════════════════\n\n"
    
    # 1. Check kernel parameters in /proc/cmdline
    verification_report+="[1] Kernel Parameters (from /proc/cmdline):\n"
    verification_report+="────────────────────────────────────────────────────\n"
    
    local required_params=()
    case "$CPU_VENDOR" in
        "intel") required_params=("intel_iommu=on" "iommu=pt") ;;
        "amd") required_params=("amd_iommu=on" "iommu=pt") ;;
    esac
    
    local param_status="✓"
    for param in "${required_params[@]}"; do
        if echo "$current_cmdline" | grep -qE "(^| )${param}( |$)"; then
            verification_report+="  ✓ $param: ACTIVE\n"
        else
            verification_report+="  ✗ $param: MISSING\n"
            param_status="✗"
            verification_failed=true
        fi
    done
    
    if [[ "$param_status" == "✓" ]]; then
        verification_report+="  Status: OK - All required params active\n"
    else
        verification_report+="  Status: FAIL - Missing required params\n"
        verification_report+="  Action: Reboot required for changes to take effect\n"
    fi
    verification_report+="\n"
    
    # 2. Check VFIO kernel modules
    verification_report+="[2] VFIO Kernel Modules (from lsmod):\n"
    verification_report+="────────────────────────────────────────────────────\n"
    
    local modules_status="✓"
    for module in "${VFIO_MODULES[@]}"; do
        if lsmod | grep -q "^${module}"; then
            verification_report+="  ✓ $module: LOADED\n"
        else
            verification_report+="  ✗ $module: NOT LOADED\n"
            modules_status="✗"
            verification_failed=true
        fi
    done
    
    if [[ "$modules_status" == "✓" ]]; then
        verification_report+="  Status: OK - All VFIO modules loaded\n"
    else
        verification_report+="  Status: FAIL - Missing modules\n"
        verification_report+="  Action: Run 'modprobe <module>' or reboot\n"
    fi
    verification_report+="\n"
    
    # 3. Check configuration files
    verification_report+="[3] Configuration Files:\n"
    verification_report+="────────────────────────────────────────────────────\n"
    
    local config_status="✓"
    
    # Check kernel cmdline file
    local cmdline_file=""
    case "$BOOT_TYPE" in
        "systemd-boot") cmdline_file="/etc/kernel/cmdline" ;;
        "grub-"*) cmdline_file="/etc/default/grub" ;;
    esac
    
    if [[ -f "$cmdline_file" ]] && [[ -s "$cmdline_file" ]]; then
        verification_report+="  ✓ Bootloader config: $cmdline_file\n"
    else
        verification_report+="  ✗ Bootloader config: Missing or empty\n"
        config_status="✗"
        verification_failed=true
    fi
    
    # Check modules-load.d
    if [[ -f "/etc/modules-load.d/vfio.conf" ]] && [[ -s "/etc/modules-load.d/vfio.conf" ]]; then
        verification_report+="  ✓ Module autoload: /etc/modules-load.d/vfio.conf\n"
    else
        verification_report+="  ✗ Module autoload: Missing or empty\n"
        config_status="✗"
        verification_failed=true
    fi
    
    # Check VFIO device config if it should exist
    if [[ -f "$VFIO_CONFIG" ]]; then
        verification_report+="  ✓ VFIO device config: $VFIO_CONFIG\n"
    else
        verification_report+="  ⚠ VFIO device config: Not yet configured\n"
    fi
    
    verification_report+="\n"
    
    # 4. IOMMU status
    verification_report+="[4] IOMMU Status:\n"
    verification_report+="────────────────────────────────────────────────────\n"
    
    if [[ -d "/sys/kernel/iommu_groups" ]]; then
        local group_count=$(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        verification_report+="  ✓ IOMMU groups: $group_count found\n"
        verification_report+="  Status: OK - IOMMU active\n"
    else
        verification_report+="  ✗ IOMMU groups: Not found\n"
        verification_report+="  Status: FAIL - IOMMU not active\n"
        verification_report+="  Action: Enable in BIOS and verify kernel params\n"
        verification_failed=true
    fi
    verification_report+="\n"
    
    # 5. Summary
    verification_report+="═══════════════════════════════════════════════════════\n"
    if $verification_failed; then
        verification_report+="  OVERALL STATUS: ✗ VERIFICATION FAILED\n"
        verification_report+="  Some components are not correctly configured.\n"
        verification_report+="  A reboot is required for kernel parameters.\n"
    else
        verification_report+="  OVERALL STATUS: ✓ VERIFICATION PASSED\n"
        verification_report+="  All components correctly configured.\n"
    fi
    verification_report+="═══════════════════════════════════════════════════════\n"
    
    # Display report
    echo -e "$verification_report" | tee -a "$LOG_FILE"
    
    whiptail --title "Configuration Verification" --scrolltext --msgbox \
        "$verification_report" 30 65
    
    if $verification_failed; then
        log_error "Configuration verification failed"
        return 1
    else
        log_success "Configuration verification passed"
        return 0
    fi
}

# ---------------------------------------------------------
# VM Template Creation Functions
# ---------------------------------------------------------

# Create VM templates optimized for GPU passthrough
create_vm_templates() {
    local choice
    choice=$(whiptail --title "VM Template Creation" --menu \
        "Select template type to create:" 15 70 4 \
        1 "Windows Gaming VM (UEFI, Q35, Gaming optimized)" \
        2 "Linux Workstation VM (UEFI, Q35, AI/Compute)" \
        3 "Media Server VM (Transcoding optimized)" \
        4 "Custom VM Template" \
        3>&1 1>&2 2>&3)
    
    case "$choice" in
        1) create_windows_gaming_template ;;
        2) create_linux_workstation_template ;;
        3) create_media_server_template ;;
        4) create_custom_template ;;
        *) return 0 ;;
    esac
}

# Windows Gaming VM Template
create_windows_gaming_template() {
    local vmid name memory cores storage
    
    vmid=$(whiptail --inputbox "Enter VM ID (100-999):" 8 40 "200" 3>&1 1>&2 2>&3)
    [[ -z "$vmid" ]] && return 1
    
    name=$(whiptail --inputbox "Enter VM name:" 8 40 "Windows-Gaming" 3>&1 1>&2 2>&3)
    [[ -z "$name" ]] && return 1
    
    memory=$(whiptail --inputbox "RAM in MB:" 8 40 "16384" 3>&1 1>&2 2>&3)
    [[ -z "$memory" ]] && return 1
    
    cores=$(whiptail --inputbox "CPU cores:" 8 40 "8" 3>&1 1>&2 2>&3)
    [[ -z "$cores" ]] && return 1
    
    storage=$(whiptail --inputbox "Disk size (GB):" 8 40 "120" 3>&1 1>&2 2>&3)
    [[ -z "$storage" ]] && return 1
    
    log_info "Creating Windows Gaming VM template..."
    
    # Check if VMID already exists
    if qm list | grep -q "^\\s*$vmid\\s"; then
        log_error "VM with ID $vmid already exists"
        whiptail --title "Error" --msgbox "VM ID $vmid already exists. Please choose a different ID." 8 50
        return 1
    fi
    
    # Create VM with corrected parameters
    qm create "$vmid" \
        --name "$name" \
        --memory "$memory" \
        --cores "$cores" \
        --sockets 1 \
        --cpu "host,hidden=1,flags=+pcid" \
        --bios "ovmf" \
        --efidisk0 "local-lvm:1" \
        --tpmstate0 "local-lvm:1,version=v2.0" \
        --scsi0 "local-lvm:${storage}" \
        --scsihw "virtio-scsi-single" \
        --net0 "virtio,bridge=vmbr0,firewall=1" \
        --bootdisk "scsi0" \
        --ostype "win11" \
        --tablet 0 \
        --args "-cpu host,kvm=off,hv_vendor_id=proxmox,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time" || {
        
        log_error "Failed to create VM"
        return 1
    }
    
    # Convert to template
    qm template "$vmid"
    
    log_success "Windows Gaming template created with ID $vmid"
    whiptail --title "Template Created" --msgbox \
        "Windows Gaming template created successfully!\n\nVM ID: $vmid\nName: $name\n\nTo use:\n1. Clone this template\n2. Add GPU via Hardware > Add > PCI Device\n3. Install Windows and GPU drivers" 15 60
}

# Linux Workstation VM Template
create_linux_workstation_template() {
    local vmid name memory cores storage
    
    vmid=$(whiptail --inputbox "Enter VM ID (100-999):" 8 40 "201" 3>&1 1>&2 2>&3)
    [[ -z "$vmid" ]] && return 1
    
    name=$(whiptail --inputbox "Enter VM name:" 8 40 "Linux-Workstation" 3>&1 1>&2 2>&3)
    [[ -z "$name" ]] && return 1
    
    memory=$(whiptail --inputbox "RAM in MB:" 8 40 "32768" 3>&1 1>&2 2>&3)
    [[ -z "$memory" ]] && return 1
    
    cores=$(whiptail --inputbox "CPU cores:" 8 40 "16" 3>&1 1>&2 2>&3)
    [[ -z "$cores" ]] && return 1
    
    storage=$(whiptail --inputbox "Disk size (GB):" 8 40 "200" 3>&1 1>&2 2>&3)
    [[ -z "$storage" ]] && return 1
    
    log_info "Creating Linux Workstation VM template..."
    
    # Check if VMID already exists
    if qm list | grep -q "^\\s*$vmid\\s"; then
        log_error "VM with ID $vmid already exists"
        whiptail --title "Error" --msgbox "VM ID $vmid already exists. Please choose a different ID." 8 50
        return 1
    fi
    
    # Create VM
    qm create "$vmid" \
        --name "$name" \
        --memory "$memory" \
        --cores "$cores" \
        --sockets 1 \
        --cpu "host" \
        --bios "ovmf" \
        --efidisk0 "local-lvm:1" \
        --scsi0 "local-lvm:${storage}" \
        --scsihw "virtio-scsi-single" \
        --net0 "virtio,bridge=vmbr0" \
        --bootdisk "scsi0" \
        --ostype "l26" \
        --tablet 0 || {
        
        log_error "Failed to create VM"
        return 1
    }
    
    # Convert to template
    qm template "$vmid"
    
    log_success "Linux Workstation template created with ID $vmid"
    whiptail --title "Template Created" --msgbox \
        "Linux Workstation template created successfully!\n\nVM ID: $vmid\nName: $name\n\nOptimized for:\n- AI/ML workloads\n- Scientific computing\n- Development work" 15 60
}

# Media Server VM Template
create_media_server_template() {
    local vmid name memory cores storage
    
    vmid=$(whiptail --inputbox "Enter VM ID (100-999):" 8 40 "202" 3>&1 1>&2 2>&3)
    [[ -z "$vmid" ]] && return 1
    
    name=$(whiptail --inputbox "Enter VM name:" 8 40 "Media-Server" 3>&1 1>&2 2>&3)
    [[ -z "$name" ]] && return 1
    
    memory=$(whiptail --inputbox "RAM in MB:" 8 40 "8192" 3>&1 1>&2 2>&3)
    [[ -z "$memory" ]] && return 1
    
    cores=$(whiptail --inputbox "CPU cores:" 8 40 "4" 3>&1 1>&2 2>&3)
    [[ -z "$cores" ]] && return 1
    
    storage=$(whiptail --inputbox "Disk size (GB):" 8 40 "50" 3>&1 1>&2 2>&3)
    [[ -z "$storage" ]] && return 1
    
    log_info "Creating Media Server VM template..."
    
    # Check if VMID already exists
    if qm list | grep -q "^\\s*$vmid\\s"; then
        log_error "VM with ID $vmid already exists"
        whiptail --title "Error" --msgbox "VM ID $vmid already exists. Please choose a different ID." 8 50
        return 1
    fi
    
    # Create VM optimized for transcoding
    qm create "$vmid" \
        --name "$name" \
        --memory "$memory" \
        --cores "$cores" \
        --sockets 1 \
        --cpu "host" \
        --bios "ovmf" \
        --efidisk0 "local-lvm:1" \
        --scsi0 "local-lvm:${storage}" \
        --scsihw "virtio-scsi-single" \
        --net0 "virtio,bridge=vmbr0" \
        --bootdisk "scsi0" \
        --ostype "l26" \
        --tablet 0 || {
        
        log_error "Failed to create VM"
        return 1
    }
    
    # Convert to template
    qm template "$vmid"
    
    log_success "Media Server template created with ID $vmid"
    whiptail --title "Template Created" --msgbox \
        "Media Server template created successfully!\n\nVM ID: $vmid\nName: $name\n\nOptimized for:\n- Plex/Jellyfin transcoding\n- Hardware acceleration\n- Low resource usage" 15 60
}

# Custom VM Template
create_custom_template() {
    whiptail --title "Custom Template" --msgbox \
        "Custom template creation allows you to specify all parameters manually.\n\nThis is for advanced users who want full control over VM configuration." 10 60
    
    local vmid name memory cores storage ostype cpu_type
    
    # Get VM parameters with validation
    while true; do
        vmid=$(whiptail --inputbox "Enter VM ID (100-999):" 8 40 "300" 3>&1 1>&2 2>&3)
        [[ -z "$vmid" ]] && return 1
        
        # Validate VMID range and availability
        if [[ "$vmid" -lt 100 || "$vmid" -gt 999 ]]; then
            whiptail --title "Invalid Input" --msgbox "VM ID must be between 100-999." 8 40
            continue
        fi
        
        if qm list | grep -q "^\\s*$vmid\\s"; then
            whiptail --title "ID Exists" --msgbox "VM ID $vmid already exists. Please choose a different ID." 8 50
            continue
        fi
        break
    done
    
    name=$(whiptail --inputbox "Enter VM name:" 8 40 "Custom-Template" 3>&1 1>&2 2>&3)
    [[ -z "$name" ]] && return 1
    
    # Memory validation
    while true; do
        memory=$(whiptail --inputbox "RAM in MB (min 512):" 8 40 "4096" 3>&1 1>&2 2>&3)
        [[ -z "$memory" ]] && return 1
        if [[ "$memory" -lt 512 ]]; then
            whiptail --title "Invalid Input" --msgbox "Memory must be at least 512 MB." 8 40
            continue
        fi
        break
    done
    
    # CPU cores validation
    local max_cores=$(nproc)
    while true; do
        cores=$(whiptail --inputbox "CPU cores (max $max_cores):" 8 40 "2" 3>&1 1>&2 2>&3)
        [[ -z "$cores" ]] && return 1
        if [[ "$cores" -lt 1 || "$cores" -gt "$max_cores" ]]; then
            whiptail --title "Invalid Input" --msgbox "CPU cores must be between 1-$max_cores." 8 40
            continue
        fi
        break
    done
    
    storage=$(whiptail --inputbox "Disk size (GB):" 8 40 "32" 3>&1 1>&2 2>&3)
    [[ -z "$storage" ]] && return 1
    
    # OS type selection
    ostype=$(whiptail --title "OS Type" --menu "Select OS type:" 15 60 6 \
        "l26" "Linux 2.6/3.x/4.x/5.x kernel" \
        "win11" "Windows 11/2022" \
        "win10" "Windows 10/2016/2019" \
        "other" "Other OS" 3>&1 1>&2 2>&3)
    [[ -z "$ostype" ]] && return 1
    
    # CPU type selection
    cpu_type=$(whiptail --title "CPU Type" --menu "Select CPU type:" 15 60 4 \
        "host" "Host CPU (best performance)" \
        "kvm64" "KVM default (compatible)" \
        "x86-64-v2" "x86-64-v2 (modern)" \
        "x86-64-v3" "x86-64-v3 (latest)" 3>&1 1>&2 2>&3)
    [[ -z "$cpu_type" ]] && return 1
    
    log_info "Creating custom VM template..."
    
    # Create VM with user-specified parameters
    qm create "$vmid" \
        --name "$name" \
        --memory "$memory" \
        --cores "$cores" \
        --sockets 1 \
        --cpu "$cpu_type" \
        --bios "ovmf" \
        --efidisk0 "local-lvm:1" \
        --scsi0 "local-lvm:${storage}" \
        --scsihw "virtio-scsi-single" \
        --net0 "virtio,bridge=vmbr0" \
        --bootdisk "scsi0" \
        --ostype "$ostype" \
        --tablet 0 || {
        
        log_error "Failed to create VM"
        return 1
    }
    
    # Convert to template
    qm template "$vmid"
    
    log_success "Custom template created with ID $vmid"
    whiptail --title "Template Created" --msgbox \
        "Custom template created successfully!\n\nVM ID: $vmid\nName: $name\nOS Type: $ostype\nCPU: $cpu_type\n\nTo add GPU passthrough:\n1. Clone this template\n2. Add GPU via Hardware > Add > PCI Device" 15 60
}

# ---------------------------------------------------------
# Rollback and Cleanup Functions
# ---------------------------------------------------------

# Complete rollback of GPU passthrough configuration
rollback_gpu_passthrough() {
    log_info "Starting complete GPU passthrough rollback..."
    
    if ! whiptail --title "Confirm Rollback" --yesno \
        "This will completely remove all GPU passthrough configuration:\n\n• Remove IOMMU kernel parameters\n• Remove VFIO configuration\n• Remove driver blacklists\n• Update initramfs\n\nThis action cannot be undone!\n\nContinue?" 15 70; then
        return 0
    fi
    
    local rollback_success=true
    
    # Remove kernel parameters
    log_info "Removing kernel parameters..."
    case "$BOOT_TYPE" in
        "systemd-boot")
            if [[ -f "/etc/kernel/cmdline" ]]; then
                cp "/etc/kernel/cmdline" "$BACKUP_DIR/cmdline.rollback.$(date +%Y%m%d_%H%M%S)"
                sed -i 's/ intel_iommu=on//g; s/ amd_iommu=on//g; s/ iommu=pt//g' /etc/kernel/cmdline
                sed -i 's/ video=efifb:off//g; s/ initcall_blacklist=sysfb_init//g' /etc/kernel/cmdline
                sed -i 's/ pcie_acs_override=downstream//g' /etc/kernel/cmdline
                pve-efiboot-tool refresh || rollback_success=false
            fi
            ;;
        "grub-uefi"|"grub-legacy")
            if [[ -f "/etc/default/grub" ]]; then
                cp "/etc/default/grub" "$BACKUP_DIR/grub.rollback.$(date +%Y%m%d_%H%M%S)"
                sed -i 's/ intel_iommu=on//g; s/ amd_iommu=on//g; s/ iommu=pt//g' /etc/default/grub
                sed -i 's/ video=efifb:off//g; s/ initcall_blacklist=sysfb_init//g' /etc/default/grub
                sed -i 's/ pcie_acs_override=downstream//g' /etc/default/grub
                update-grub || rollback_success=false
            fi
            ;;
    esac
    
    # Remove configuration files
    log_info "Removing configuration files..."
    local configs=("$VFIO_CONFIG" "$BLACKLIST_CONFIG" "$KVM_CONFIG" "/etc/modules-load.d/vfio.conf" "/etc/modprobe.d/vfio_iommu_type1.conf")
    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            mv "$config" "$BACKUP_DIR/$(basename "$config").removed.$(date +%Y%m%d_%H%M%S)" || rollback_success=false
        fi
    done
    
    # Remove PECU-managed repository file (optional)
    if whiptail --title "Remove Repository Config" --yesno \
        "Also remove PECU-managed APT repository configuration?\n\nFile: /etc/apt/sources.list.d/pecu-repos.list\n\nYour system repositories will not be affected." 10 70; then
        remove_pecu_repos "/etc/apt/sources.list.d/pecu-repos.list"
        # Clean up old legacy file if exists
        if [[ -f "/etc/apt/sources.list.d/pve-install.list" ]]; then
            log_info "Removing legacy repository file..."
            mv "/etc/apt/sources.list.d/pve-install.list" "$BACKUP_DIR/pve-install.list.removed.$(date +%Y%m%d_%H%M%S)"
        fi
    fi
    
    # Remove vendor-reset if installed
    if lsmod | grep -q "vendor_reset"; then
        log_info "Removing vendor-reset..."
        rmmod vendor_reset 2>/dev/null || true
        if dkms status | grep -q "vendor-reset"; then
            dkms remove vendor-reset --all || true
        fi
        sed -i '/vendor-reset/d' /etc/modules
    fi
    
    # Update initramfs
    log_info "Updating initramfs..."
    update-initramfs -u -k all || rollback_success=false
    
    # Reset state file
    cat > "$STATE_FILE" << EOF
# PECU Configuration State File - Reset on $(date)
INITIALIZED=true
IOMMU_CONFIGURED=false
VFIO_CONFIGURED=false
GPU_BLACKLISTED=false
PASSTHROUGH_READY=false
EOF
    
    if $rollback_success; then
        log_success "GPU passthrough rollback completed successfully"
        whiptail --title "Rollback Complete" --msgbox \
            "GPU passthrough configuration has been completely removed.\n\nA reboot is required to apply all changes.\n\nReboot now?" 10 60
        if [[ $? -eq 0 ]]; then
            reboot
        fi
    else
        log_error "Some rollback operations failed"
        whiptail --title "Rollback Issues" --msgbox \
            "Rollback completed with some errors.\nCheck the log file for details: $LOG_FILE" 8 60
    fi
    
    return $?
}

# ---------------------------------------------------------
# Utility Functions
# ---------------------------------------------------------

# Show loading banner
show_loading_banner() {
    clear
    
    # Banner principal
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                                           ║${NC}"
    echo -e "${BLUE}║${YELLOW}            ██████╗ ███████╗ ██████╗██╗   ██╗                            ${BLUE}║${NC}"
    echo -e "${BLUE}║${YELLOW}            ██╔══██╗██╔════╝██╔════╝██║   ██║                            ${BLUE}║${NC}"
    echo -e "${BLUE}║${YELLOW}            ██████╔╝█████╗  ██║     ██║   ██║                            ${BLUE}║${NC}"
    echo -e "${BLUE}║${YELLOW}            ██╔═══╝ ██╔══╝  ██║     ██║   ██║                            ${BLUE}║${NC}"
    echo -e "${BLUE}║${YELLOW}            ██║     ███████╗╚██████╗╚██████╔╝                            ${BLUE}║${NC}"
    echo -e "${BLUE}║${YELLOW}            ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝                             ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                                           ║${NC}"
    echo -e "${BLUE}║${CYAN}              PROXMOX ENHANCED CONFIGURATION UTILITY                      ${BLUE}║${NC}"
    echo -e "${BLUE}║${CYAN}                GPU Passthrough Configuration Suite                       ${BLUE}║${NC}"
    echo -e "${BLUE}║${PURPLE}                          Version 3.1                                     ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                                           ║${NC}"
    echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║                                                                           ║${NC}"
    echo -e "${BLUE}║${GREEN}  Developer:${NC}  Daniel Puente García                                       ${BLUE}║${NC}"
    echo -e "${BLUE}║${GREEN}  GitHub:${NC}     @Danilop95                                                  ${BLUE}║${NC}"
    echo -e "${BLUE}║${GREEN}  Support:${NC}    https://buymeacoffee.com/danilop95                         ${BLUE}║${NC}"
    echo -e "${BLUE}║${GREEN}  Website:${NC}    https://pecu.tools                                         ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                                           ║${NC}"
    echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${CYAN}  Features:${NC}                                                               ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    • NVIDIA, AMD & Intel GPU Support (including datacenter cards)       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    • Automated IOMMU & VFIO Configuration                                ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    • Bootloader Detection (systemd-boot/GRUB)                            ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    • Idempotent Repository Management                                    ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    • VM Template Creation & Management                                   ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                                           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    sleep 2
    clear
}

# Progress indicator
progress_indicator() {
    local msg="$1"
    local duration="${2:-3}"
    
    {
        for i in $(seq 0 10 100); do
            echo $i
            echo "XXX"
            echo "$msg"
            echo "XXX"
            sleep 0.$(($duration * 10 / 10))
        done
    } | whiptail --gauge "$msg" 8 60 0
}

# Ask for reboot
ask_for_reboot() {
    if whiptail --title "Reboot Required" --yesno \
        "A system reboot is required to apply the changes.\n\nReboot now?" 8 50; then
        log_info "User requested reboot"
        sync
        reboot
    else
        log_info "Reboot postponed by user"
        whiptail --title "Reboot Postponed" --msgbox \
            "Changes will take effect after next reboot.\n\nDon't forget to reboot when convenient!" 8 60
    fi
}



# ---------------------------------------------------------
# Complete GPU Passthrough Configuration Workflow
# ---------------------------------------------------------

# Complete automated GPU passthrough setup
complete_gpu_passthrough_setup() {
    log_info "Starting complete GPU passthrough configuration..."
    
    # Step 1: System detection and validation
    log_info "Step 1/8: System detection and hardware validation"
    progress_indicator "Detecting system configuration..." 2
    
    detect_system_info
    if ! check_hardware_requirements; then
        return 1
    fi
    
    # Step 2: GPU detection
    log_info "Step 2/8: GPU detection and IOMMU analysis"
    progress_indicator "Scanning for GPU devices..." 2
    
    if ! detect_gpus; then
        return 1
    fi
    
    if ! check_iommu_groups; then
        if ! whiptail --title "IOMMU Issues" --yesno \
            "IOMMU group issues detected. Continue anyway?\n(You may need ACS override)" 8 60; then
            return 1
        fi
    fi
    
    # Step 3: Install dependencies
    log_info "Step 3/8: Installing dependencies"
    progress_indicator "Installing required packages..." 3
    
    configure_sources_list
    install_dependencies
    
    # Step 4: Configure IOMMU
    log_info "Step 4/8: Configuring IOMMU"
    progress_indicator "Configuring IOMMU kernel parameters..." 2
    
    if ! configure_iommu; then
        log_error "Failed to configure IOMMU"
        return 1
    fi
    
    # Ask about additional parameters
    if whiptail --title "Additional Parameters" --yesno \
        "Configure additional kernel parameters?\n(Recommended for better compatibility)" 8 60; then
        configure_additional_parameters
    fi
    
    # Step 5: Configure VFIO
    log_info "Step 5/8: Configuring VFIO modules"
    progress_indicator "Setting up VFIO modules..." 2
    
    if ! configure_vfio_modules; then
        log_error "Failed to configure VFIO modules"
        return 1
    fi
    
    # Step 6: Blacklist drivers
    log_info "Step 6/8: Configuring GPU driver blacklist"
    progress_indicator "Configuring driver blacklist..." 2
    
    if ! blacklist_gpu_drivers; then
        log_error "Failed to configure driver blacklist"
        return 1
    fi
    
    # Step 7: Configure VFIO device IDs
    log_info "Step 7/8: Configuring VFIO device bindings"
    progress_indicator "Setting up VFIO device bindings..." 2
    
    if ! configure_vfio_device_ids; then
        log_error "Failed to configure VFIO device IDs"
        return 1
    fi
    
    # Step 8: Additional configurations
    log_info "Step 8/8: Final configurations"
    progress_indicator "Applying final configurations..." 2
    
    configure_kvm_options
    
    # Ask about vendor-reset for AMD
    if lspci | grep -q "AMD" && whiptail --title "AMD GPU Reset" --yesno \
        "Install vendor-reset for AMD GPU reset bug fix?" 8 60; then
        install_vendor_reset
    fi
    
    # Update state
    sed -i 's/PASSTHROUGH_READY=false/PASSTHROUGH_READY=true/' "$STATE_FILE"
    
    log_success "Complete GPU passthrough configuration finished!"
    
    # Run live verification
    log_info "Running post-configuration verification..."
    verify_configuration_live
    
    # Summary
    whiptail --title "Configuration Complete" --msgbox \
        "GPU Passthrough configuration completed successfully!\n\n✅ IOMMU configured\n✅ VFIO modules set up\n✅ GPU drivers blacklisted\n✅ Device bindings configured\n✅ KVM options optimized\n\nNext steps:\n1. REBOOT the system\n2. Verify configuration after reboot\n3. Create VM templates\n4. Add GPU to VMs via Hardware menu\n\nReboot now?" 20 60
    
    if [[ $? -eq 0 ]]; then
        ask_for_reboot
    fi
    
    return 0
}

# ---------------------------------------------------------
# Main Menu System
# ---------------------------------------------------------

# Hardware and detection submenu
hardware_detection_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Hardware Detection & Validation" --menu \
            "System hardware detection and validation options:" 20 75 10 \
            1 "Check Hardware Requirements" \
            2 "Detect System Information" \
            3 "Scan for GPU Devices" \
            4 "Analyze IOMMU Groups" \
            5 "Check Current Passthrough Status" \
            6 "Live Configuration Verification" \
            7 "View System Logs (dmesg)" \
            8 "Test VFIO Module Loading" \
            9 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "$choice" in
            1) check_hardware_requirements ;;
            2) 
                detect_system_info
                whiptail --title "System Info" --msgbox \
                    "CPU Vendor: $CPU_VENDOR\nBoot Type: $BOOT_TYPE\nIOMMU Status: $IOMMU_STATUS" 10 50
                ;;
            3) detect_gpus ;;
            4) check_iommu_groups ;;
            5) check_passthrough_status ;;
            6) verify_configuration_live ;;
            7) 
                local dmesg_output=$(dmesg | grep -i "iommu\|vfio\|amd-vi\|dmar" | tail -20)
                whiptail --title "System Logs" --scrolltext --msgbox "$dmesg_output" 20 80
                ;;
            8)
                log_info "Testing VFIO module loading..."
                for module in "${VFIO_MODULES[@]}"; do
                    if modprobe "$module" 2>/dev/null; then
                        log_success "Module $module loaded successfully"
                    else
                        log_error "Failed to load module $module"
                    fi
                done
                ;;
            9) break ;;
            *) break ;;
        esac
    done
}

# Configuration submenu
configuration_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "GPU Passthrough Configuration" --menu \
            "Configure GPU passthrough components:" 20 75 12 \
            1 "Configure IOMMU (Kernel Parameters)" \
            2 "Configure VFIO Modules" \
            3 "Configure GPU Driver Blacklist" \
            4 "Configure VFIO Device Bindings" \
            5 "Configure KVM Options" \
            6 "Configure Additional Kernel Parameters" \
            7 "Install vendor-reset (AMD GPU Fix)" \
            8 "Configure APT Sources (Idempotent)" \
            9 "Preview Repository Changes (Dry-Run)" \
            10 "Show Repository Status" \
            11 "Install Dependencies" \
            12 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "$choice" in
            1) configure_iommu ;;
            2) configure_vfio_modules ;;
            3) blacklist_gpu_drivers ;;
            4) configure_vfio_device_ids ;;
            5) configure_kvm_options ;;
            6) configure_additional_parameters ;;
            7) install_vendor_reset ;;
            8) configure_sources_list ;;
            9) preview_repo_changes ;;
            10) show_repo_status ;;
            11) install_dependencies ;;
            12) break ;;
            *) break ;;
        esac
    done
}

# VM and templates submenu
vm_templates_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "VM Templates & Management" --menu \
            "Create and manage VM templates for GPU passthrough:" 15 70 6 \
            1 "Create Windows Gaming Template" \
            2 "Create Linux Workstation Template" \
            3 "Create Media Server Template" \
            4 "Create Custom Template" \
            5 "List Existing Templates" \
            6 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "$choice" in
            1) create_windows_gaming_template ;;
            2) create_linux_workstation_template ;;
            3) create_media_server_template ;;
            4) create_custom_template ;;
            5) 
                local templates=$(qm list | grep "template")
                if [[ -n "$templates" ]]; then
                    whiptail --title "Existing Templates" --scrolltext --msgbox "$templates" 15 80
                else
                    whiptail --title "Templates" --msgbox "No templates found." 8 40
                fi
                ;;
            6) break ;;
            *) break ;;
        esac
    done
}

# Advanced tools submenu
advanced_tools_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Advanced Tools & Troubleshooting" --menu \
            "Advanced configuration and troubleshooting tools:" 15 70 7 \
            1 "Complete Rollback (Remove All Configuration)" \
            2 "View Configuration Files" \
            3 "Manual Kernel Parameter Editor" \
            4 "VFIO Device Unbind/Rebind" \
            5 "System Backup & Restore" \
            6 "View Detailed Logs" \
            7 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "$choice" in
            1) rollback_gpu_passthrough ;;
            2) 
                local files="$VFIO_CONFIG\n$BLACKLIST_CONFIG\n$KVM_CONFIG\n/etc/modules-load.d/vfio.conf"
                local file_choice
                file_choice=$(whiptail --title "View Config Files" --menu "Select file to view:" 12 60 4 \
                    1 "VFIO Config" \
                    2 "Blacklist Config" \
                    3 "KVM Config" \
                    4 "VFIO Modules" \
                    3>&1 1>&2 2>&3)
                
                case "$file_choice" in
                    1) [[ -f "$VFIO_CONFIG" ]] && whiptail --title "VFIO Config" --textbox "$VFIO_CONFIG" 20 80 || whiptail --title "Error" --msgbox "File not found: $VFIO_CONFIG" 8 50 ;;
                    2) [[ -f "$BLACKLIST_CONFIG" ]] && whiptail --title "Blacklist Config" --textbox "$BLACKLIST_CONFIG" 20 80 || whiptail --title "Error" --msgbox "File not found: $BLACKLIST_CONFIG" 8 50 ;;
                    3) [[ -f "$KVM_CONFIG" ]] && whiptail --title "KVM Config" --textbox "$KVM_CONFIG" 20 80 || whiptail --title "Error" --msgbox "File not found: $KVM_CONFIG" 8 50 ;;
                    4) [[ -f "/etc/modules-load.d/vfio.conf" ]] && whiptail --title "VFIO Modules" --textbox "/etc/modules-load.d/vfio.conf" 20 80 || whiptail --title "Error" --msgbox "File not found: /etc/modules-load.d/vfio.conf" 8 50 ;;
                esac
                ;;
            3) 
                # Manual kernel parameter editor
                local current_params=""
                case "$BOOT_TYPE" in
                    "systemd-boot")
                        [[ -f "/etc/kernel/cmdline" ]] && current_params=$(cat /etc/kernel/cmdline)
                        ;;
                    "grub-uefi"|"grub-legacy")
                        [[ -f "/proc/cmdline" ]] && current_params=$(cat /proc/cmdline)
                        ;;
                esac
                
                whiptail --title "Current Kernel Parameters" --scrolltext --msgbox \
                    "Current kernel parameters:\n\n$current_params\n\nUse the configuration menus to modify parameters safely." 15 80
                ;;
            4) 
                # VFIO device management
                local bound_devices=$(find /sys/bus/pci/drivers/vfio-pci -name "0000:*" 2>/dev/null | wc -l)
                local vfio_info="VFIO-bound devices: $bound_devices\n\n"
                
                if [[ $bound_devices -gt 0 ]]; then
                    vfio_info+="Bound devices:\n"
                    for device in $(find /sys/bus/pci/drivers/vfio-pci -name "0000:*" 2>/dev/null); do
                        local device_id=$(basename "$device")
                        local device_desc=$(lspci -s "$device_id" 2>/dev/null | cut -d' ' -f2-)
                        vfio_info+="- $device_id: $device_desc\n"
                    done
                else
                    vfio_info+="No devices currently bound to VFIO.\n"
                fi
                
                vfio_info+="\nFor manual device management, use:\necho 'DEVICE_ID' > /sys/bus/pci/drivers/vfio-pci/bind\necho 'DEVICE_ID' > /sys/bus/pci/drivers/vfio-pci/unbind"
                
                whiptail --title "VFIO Device Management" --scrolltext --msgbox "$vfio_info" 20 80
                ;;
            5) 
                local backup_info="Backup directory: $BACKUP_DIR\nFiles backed up: $(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)"
                whiptail --title "Backup Information" --msgbox "$backup_info" 10 50
                ;;
            6) 
                if [[ -f "$LOG_FILE" ]]; then
                    local tmp_log=$(mktemp)
                    tail -50 "$LOG_FILE" > "$tmp_log"
                    whiptail --title "PECU Logs" --textbox "$tmp_log" 20 80
                    rm -f "$tmp_log"
                else
                    whiptail --title "Logs" --msgbox "No log file found." 8 40
                fi
                ;;
            7) break ;;
            *) break ;;
        esac
    done
}

# Help and information submenu
help_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Help & Information" --menu \
            "Help, documentation, and support information:" 15 70 7 \
            1 "About PECU" \
            2 "GPU Passthrough Guide" \
            3 "Troubleshooting Tips" \
            4 "Support & Sponsorship" \
            5 "System Requirements" \
            6 "View License" \
            7 "Back to Main Menu" \
            3>&1 1>&2 2>&3)
        
        case "$choice" in
            1) 
                whiptail --title "About PECU" --msgbox \
                    "Proxmox Enhanced Configuration Utility (PECU) v$VERSION\n\nA comprehensive tool for configuring GPU passthrough on Proxmox VE systems.\n\nAuthor: $AUTHOR\nBuild Date: $BUILD_DATE\nGitHub: github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility" 15 70
                ;;
            2) 
                whiptail --title "GPU Passthrough Guide" --msgbox \
                    "GPU Passthrough Setup Process:\n\n1. Enable IOMMU in BIOS/UEFI\n2. Configure IOMMU kernel parameters\n3. Load VFIO modules\n4. Blacklist GPU host drivers\n5. Bind GPU to VFIO\n6. Create VM with Q35 chipset and UEFI\n7. Add GPU as PCI device\n8. Install guest OS and GPU drivers\n\nUse 'Complete Setup' for automated configuration." 18 70
                ;;
            3) 
                whiptail --title "Troubleshooting" --msgbox \
                    "Common Issues:\n\n• No IOMMU groups: Enable VT-d/AMD-Vi in BIOS\n• GPU not isolated: May need ACS override\n• Code 43 (NVIDIA): Use hidden CPU flag\n• AMD reset bug: Install vendor-reset\n• VM won't start: Check UEFI and Q35 chipset\n• No display: GPU may need monitor connected\n\nCheck logs in /var/log/pecu.log for details." 16 70
                ;;
            4) 
                whiptail --title "Support PECU" --msgbox \
                    "PECU is developed and maintained by:\n$AUTHOR\n\nIf you find this tool useful, please consider supporting development:\n\n• BuyMeACoffee: $BMAC_URL\n• Patreon: $PATRON_URL\n\nYour support helps improve and maintain this tool!" 15 70
                ;;
            5) 
                whiptail --title "System Requirements" --msgbox \
                    "GPU Passthrough Requirements:\n\n• CPU with VT-x/AMD-V and VT-d/AMD-Vi\n• Motherboard with IOMMU support\n• GPU with UEFI GOP support (recommended)\n• Sufficient RAM for host and guest\n• Proxmox VE 7.0+ (8.x recommended)\n\nOptional:\n• Second GPU for host display\n• IPMI for remote access" 16 70
                ;;
            6) 
                whiptail --title "License" --msgbox \
                    "MIT License\n\nCopyright (c) 2025 Daniel Puente García\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software." 15 70
                ;;
            7) break ;;
            *) break ;;
        esac
    done
}

# Main menu
main_menu() {
    while true; do
        local choice
        choice=$(whiptail --backtitle "PECU v$VERSION | By Daniel Puente García (@Danilop95) | Support: buymeacoffee.com/danilop95 | pecu.tools" \
            --title "PROXMOX ENHANCED CONFIG UTILITY" --menu \
            "Complete GPU passthrough configuration and management suite\nSupports NVIDIA, AMD, Intel GPUs | IOMMU | VFIO | VM Templates\n\nSelect an option:" \
            20 80 9 \
            1 "Complete GPU Passthrough Setup (Recommended)" \
            2 "Hardware Detection & Validation" \
            3 "GPU Passthrough Configuration" \
            4 "VM Templates & Management" \
            5 "Advanced Tools & Troubleshooting" \
            6 "Help & Information" \
            7 "View Current Status" \
            8 "Reboot System" \
            9 "Exit PECU" \
            3>&1 1>&2 2>&3)
        
        case "$choice" in
            1) complete_gpu_passthrough_setup ;;
            2) hardware_detection_menu ;;
            3) configuration_menu ;;
            4) vm_templates_menu ;;
            5) advanced_tools_menu ;;
            6) help_menu ;;
            7) check_passthrough_status ;;
            8) ask_for_reboot ;;
            9) 
                if whiptail --title "Exit PECU" --yesno \
                    "Thank you for using PECU!\n\nAre you sure you want to exit?" 8 50; then
                    break
                fi
                ;;
            *) break ;;
        esac
    done
}

# ---------------------------------------------------------
# Main Function and Script Entry Point
# ---------------------------------------------------------

main() {
    # Root check
    check_root
    
    # Check system dependencies
    check_deps
    
    # Initialize environment
    create_directories
    
    # Show loading banner
    show_loading_banner
    
    # Initialize system detection
    detect_system_info
    
    # Start main menu
    main_menu
    
    # Exit message
    clear
    echo -e "${GREEN}Thank you for using PECU v$VERSION!${NC}"
    echo -e "${CYAN}GPU Passthrough Configuration Utility${NC}"
    echo -e "${YELLOW}By $AUTHOR${NC}"
    echo ""
    echo -e "${BLUE}Support development: $BMAC_URL${NC}"
    echo ""
    
    log_success "PECU session ended"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

exit 0
