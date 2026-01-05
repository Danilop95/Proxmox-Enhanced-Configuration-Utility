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
#  Version:       3.2.2                                                       #
#  Release Date:  January 5, 2026                                             #
#                                                                              #
#  ──────────────────────────────────────────────────────────────────────────  #
#                                                                              #
# Support this project:                                                   #
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
#  Supported Systems:                                                         #
#    • Proxmox VE 7.x (Debian 11 - Bullseye)                                  #
#    • Proxmox VE 8.x (Debian 12 - Bookworm)                                  #
#    • Proxmox VE 9.x (Debian 13 - Trixie)                                    #
#                                                                              #
#  License:       MIT License                                                 #
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
VERSION="3.2.2"
BUILD_DATE="2026-01-05"
BMAC_URL="https://buymeacoffee.com/danilop95"
PATRON_URL="https://patreon.com/danilop95"
WEBSITE_URL="https://pecu.tools"

# Configuration constants
VFIO_MODULES=("vfio" "vfio_pci" "vfio_iommu_type1")
NVIDIA_MODULES=("nouveau" "nvidia" "nvidiafb")
AMD_MODULES=("amdgpu" "radeon")
INTEL_MODULES=("i915")

# ---------------------------------------------------------
# VM Template Defaults (Chipset / Machine Type)
# ---------------------------------------------------------
# NOTE (Issue #28):
# Early test builds used i440fx as a "safe default" while validating the template
# across different Proxmox hosts/versions and GPU setups. From v3.2.2 the default
# is Q35 + UEFI for the Windows 11 Gaming template (and other templates).
DEFAULT_MACHINE_WIN_GAMING="q35"
DEFAULT_MACHINE_LINUX_WORKSTATION="q35"
DEFAULT_MACHINE_MEDIA_SERVER="q35"
DEFAULT_MACHINE_CUSTOM="q35"

# Global configuration directories and files
BACKUP_DIR="/root/pecu-backup"
STATE_FILE="$BACKUP_DIR/pecu_state.conf"
LOG_FILE="/var/log/pecu.log"
CONFIG_DIR="/etc/pecu"
ISO_LAST_VOLID=""
VFIO_CONFIG="/etc/modprobe.d/vfio.conf"
BLACKLIST_CONFIG="/etc/modprobe.d/blacklist-gpu.conf"
KVM_CONFIG="/etc/modprobe.d/kvm.conf"
VFIO_IOMMU_CONFIG="/etc/modprobe.d/vfio_iommu_type1.conf"

# Detection flags
declare -A DETECTED_GPUS
declare -A GPU_IOMMU_GROUPS
declare -A GPU_DEVICE_IDS
declare -A GPU_DRIVER_IN_USE
declare -A GPU_IS_VF
declare -A GPU_IS_PF
declare -A GPU_SLOT
declare -A GPU_CLASS
declare -A GPU_PF_BDF

# System information
CPU_VENDOR=""
BOOT_TYPE=""
IOMMU_STATUS=""

# ---------------------------------------------------------
# Filesystem + state initialization
# ---------------------------------------------------------

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
        chmod 600 "$STATE_FILE" 2>/dev/null || true
    fi
}

# Cleanup function for temporary files and processes
cleanup_on_exit() {
    local exit_code=$?
    trap - EXIT INT TERM

    # Kill any child whiptail/dialog processes to avoid zombies on lost TTY
    if command -v pkill >/dev/null 2>&1; then
        pkill -P $$ whiptail 2>/dev/null || true
        pkill -P $$ dialog 2>/dev/null || true
    fi

    # Clean up temporary files older than 1 day (safe with spaces)
    find /tmp -name "pecu_*" -type f -mtime +1 -exec rm -f {} + 2>/dev/null || true

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

# ---------------------------------------------------------
# Enhanced logging system
# ---------------------------------------------------------

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

    # Ensure log directory writable
    if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
        echo -e "${RED}Warning: Cannot write to log directory $(dirname "$LOG_FILE")${NC}" >&2
        echo -e "${color}[$timestamp] [$level] $message${NC}" >&2
        return 1
    fi

    # Rotate log file if it gets too large (> 10MB)
    if [[ -f "$LOG_FILE" ]]; then
        local sz
        sz=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ "$sz" -gt 10485760 ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
            echo "[$timestamp] [INFO] Log file rotated" > "$LOG_FILE"
        fi
    fi

    # IMPORTANT: print to STDERR so command substitutions stay clean
    echo -e "${color}[$timestamp] [$level] $message${NC}" | tee -a "$LOG_FILE" >&2
}

log_info() { log_message "INFO" "$1"; }
log_error() { log_message "ERROR" "$1"; }
log_warning() { log_message "WARNING" "$1"; }
log_success() { log_message "SUCCESS" "$1"; }
log_debug() { log_message "DEBUG" "$1"; }

# ---------------------------------------------------------
# Helper / PCI utilities (NEW in v3.2)
# ---------------------------------------------------------

normalize_bdf() {
    local bdf="$1"
    [[ -z "$bdf" ]] && return 1
    # If already 0000:BB:DD.F
    if [[ "$bdf" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$ ]]; then
        echo "$bdf"
        return 0
    fi
    # If BB:DD.F
    if [[ "$bdf" =~ ^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$ ]]; then
        echo "0000:$bdf"
        return 0
    fi
    # If lspci output includes extra fields, take first token and retry
    local first="${bdf%% *}"
    if [[ "$first" != "$bdf" ]]; then
        normalize_bdf "$first"
        return $?
    fi
    return 1
}

is_valid_vendor_device() {
    local id="$1"
    [[ "$id" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$ ]]
}

get_pci_vendor_device() {
    local bdf
    bdf=$(normalize_bdf "$1") || return 1
    lspci -n -s "$bdf" 2>/dev/null | awk '{print $3}' | head -n1
}

get_pci_class_code() {
    local bdf
    bdf=$(normalize_bdf "$1") || return 1
    lspci -Dn -s "$bdf" 2>/dev/null | awk '{print $2}' | head -n1 | tr -d ':'
}

get_pci_human_desc() {
    local bdf
    bdf=$(normalize_bdf "$1") || return 1
    lspci -D -s "$bdf" 2>/dev/null | cut -d' ' -f2-
}

get_pci_driver_in_use() {
    local bdf
    bdf=$(normalize_bdf "$1") || return 1
    local link="/sys/bus/pci/devices/$bdf/driver"
    if [[ -L "$link" ]]; then
        basename "$(readlink -f "$link")"
    else
        echo "none"
    fi
}

get_pci_iommu_group() {
    local bdf
    bdf=$(normalize_bdf "$1") || return 1
    local link="/sys/bus/pci/devices/$bdf/iommu_group"
    if [[ -L "$link" ]]; then
        basename "$(readlink -f "$link")"
    else
        echo ""
    fi
}

is_sriov_vf() {
    local bdf
    bdf=$(normalize_bdf "$1") || return 1
    [[ -e "/sys/bus/pci/devices/$bdf/physfn" ]]
}

get_sriov_pf_bdf() {
    local bdf
    bdf=$(normalize_bdf "$1") || return 1
    if [[ -L "/sys/bus/pci/devices/$bdf/physfn" ]]; then
        basename "$(readlink -f "/sys/bus/pci/devices/$bdf/physfn")"
    else
        echo ""
    fi
}

is_sriov_pf() {
    local bdf
    bdf=$(normalize_bdf "$1") || return 1
    local sys="/sys/bus/pci/devices/$bdf"
    if [[ -r "$sys/sriov_totalvfs" ]]; then
        local total
        total=$(cat "$sys/sriov_totalvfs" 2>/dev/null || echo 0)
        [[ "$total" -gt 0 ]]
    else
        return 1
    fi
}

create_cmdline_from_proc() {
    local cmdline=""
    if [[ -r /proc/cmdline ]]; then
        cmdline=$(cat /proc/cmdline)
        # Remove transient params that should not be in /etc/kernel/cmdline
        cmdline=$(echo "$cmdline" | sed -E 's/(^| )BOOT_IMAGE=[^ ]+//g; s/(^| )initrd=[^ ]+//g; s/  */ /g; s/^ //; s/ $//')
    fi
    echo "$cmdline"
}

# Escape arbitrary text for grep -E (ERE)
escape_ere() {
    printf '%s' "$1" | sed -e 's/[][(){}.^$?+*|\/]/\\&/g'
}

# Escape replacement text for sed s/// (handles \, / and &)
escape_sed_repl() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g; s/[\/&]/\\&/g'
}

# Check if a cmdline string contains a parameter base (e.g. "iommu", "vfio-pci.disable_vga")
# Matches: start/space + needle + (= or space or end)
cmdline_has_param() {
    local haystack="$1"
    local needle="$2"
    local esc
    esc="$(escape_ere "$needle")"
    grep -qE "(^|[[:space:]])${esc}([=]|[[:space:]]|$)" <<<"$haystack"
}

# Validate /etc/modprobe.d/vfio.conf to avoid "bad line" errors (Issue #21 / #33)
validate_vfio_conf() {
    local file="${1:-$VFIO_CONFIG}"
    if [[ ! -f "$file" ]]; then
        log_warning "VFIO config not found: $file"
        return 1
    fi

    local options_lines=0
    local bad_count=0
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Ignore comments/blank
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^[[:space:]]*options[[:space:]]+vfio-pci[[:space:]]+ ]]; then
            ((options_lines++))
            if [[ "$line" =~ ids=([^[:space:]]+) ]]; then
                local ids="${BASH_REMATCH[1]}"
                IFS=',' read -r -a arr <<< "$ids"
                for id in "${arr[@]}"; do
                    if ! is_valid_vendor_device "$id"; then
                        log_warning "vfio.conf invalid ID '$id' in: $line"
                        ((bad_count++))
                        break
                    fi
                done
            fi
        else
            log_warning "vfio.conf bad line: $line"
            ((bad_count++))
        fi
    done < "$file"

    if [[ "$options_lines" -eq 0 ]]; then
        log_warning "vfio.conf has no 'options vfio-pci ...' line"
        ((bad_count++))
    fi

    if [[ "$bad_count" -gt 0 ]]; then
        log_error "VFIO config validation failed ($bad_count issue(s))"
        return 1
    fi

    log_success "VFIO config validation passed"
    return 0
}

# Repair invalid vfio.conf by collapsing stray PCI IDs into one valid "options vfio-pci ids=..." line
repair_vfio_conf() {
    log_info "Repairing vfio.conf (if needed)..."

    if [[ ! -f "$VFIO_CONFIG" ]]; then
        whiptail --title "Repair VFIO Config" --msgbox "File not found:\n$VFIO_CONFIG" 9 60
        return 1
    fi

    if validate_vfio_conf "$VFIO_CONFIG"; then
        whiptail --title "Repair VFIO Config" --msgbox "vfio.conf already looks valid.\nNo repair needed." 9 60
        return 0
    fi

    local ids_found
    ids_found=$(grep -oE '[0-9a-fA-F]{4}:[0-9a-fA-F]{4}' "$VFIO_CONFIG" 2>/dev/null | tr 'A-F' 'a-f' | sort -u)

    if [[ -z "$ids_found" ]]; then
        whiptail --title "Repair VFIO Config" --msgbox \
            "No vendor:device IDs were found inside vfio.conf.\nPECU cannot auto-repair it.\n\nOpen the file and fix it manually:\n$VFIO_CONFIG" 13 70
        return 1
    fi

    local ids_csv
    ids_csv=$(echo "$ids_found" | paste -sd, -)

    local preview="PECU detected these IDs in your vfio.conf:\n\n$ids_found\n\nPECU can rewrite vfio.conf into a single valid line:\n\noptions vfio-pci ids=$ids_csv disable_vga=1\n\nProceed? A backup will be created in:\n$BACKUP_DIR"
    if ! whiptail --title "Repair VFIO Config" --scrolltext --yesno "$preview" 22 90; then
        return 0
    fi

    cp "$VFIO_CONFIG" "$BACKUP_DIR/$(basename "$VFIO_CONFIG").repair.bak.$(date +%Y%m%d_%H%M%S)"

    cat > "$VFIO_CONFIG" << EOF
# VFIO GPU configuration (REPAIRED)
# Rewritten by PECU on $(date)
# Original saved in $BACKUP_DIR
options vfio-pci ids=$ids_csv disable_vga=1
EOF
    chmod 644 "$VFIO_CONFIG"

    if validate_vfio_conf "$VFIO_CONFIG"; then
        whiptail --title "Repair VFIO Config" --msgbox "vfio.conf repaired and validated successfully." 9 60
        return 0
    else
        whiptail --title "Repair VFIO Config" --msgbox \
            "PECU rewrote vfio.conf but validation still fails.\nCheck:\n$VFIO_CONFIG\nand log:\n$LOG_FILE" 12 70
        return 1
    fi
}

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
    for bin in whiptail lspci qm pveversion awk sed grep find dmesg modprobe lsmod readlink sort paste wc head tail pvesm; do
        command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
    done
    if (( ${#missing[@]} )); then
        log_error "Missing dependencies: ${missing[*]}"
        echo -e "${RED}Error: Missing required commands: ${missing[*]}${NC}"
        echo -e "${YELLOW}Please install missing packages and run again.${NC}"
        exit 1
    fi

    # Verify at least one HTTP client exists for ISO downloads
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_error "Missing HTTP client: curl or wget required for ISO downloads"
        echo -e "${RED}Error: Neither curl nor wget found${NC}"
        echo -e "${YELLOW}Install curl or wget: apt install curl${NC}"
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

    # Detect boot type
    BOOT_TYPE=$(detect_bootloader)
    case "$BOOT_TYPE" in
        "systemd-boot") log_info "Detected UEFI with systemd-boot" ;;
        "grub-uefi") log_info "Detected UEFI with GRUB" ;;
        "grub-legacy") log_info "Detected Legacy BIOS with GRUB" ;;
        *) log_warning "Unknown boot type: $BOOT_TYPE" ;;
    esac

    # Check IOMMU status
    if dmesg | grep -qiE "IOMMU|DMAR|AMD-Vi" && [[ -d "/sys/kernel/iommu_groups" ]]; then
        IOMMU_STATUS="enabled"
        log_success "IOMMU is enabled and active"
    elif dmesg | grep -qiE "IOMMU|DMAR|AMD-Vi"; then
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

    if [[ -d "/sys/firmware/efi" ]]; then
        # Prefer positive detection of systemd-boot without mutating the host
        if [[ -f "/etc/kernel/cmdline" ]] && (command -v proxmox-boot-tool >/dev/null 2>&1 || command -v pve-efiboot-tool >/dev/null 2>&1); then
            boot_type="systemd-boot"
        elif [[ -d "/boot/efi/loader/entries" ]]; then
            boot_type="systemd-boot"
        elif command -v bootctl >/dev/null 2>&1 && bootctl is-installed >/dev/null 2>&1; then
            boot_type="systemd-boot"
        else
            boot_type="grub-uefi"
        fi
    else
        boot_type="grub-legacy"
    fi

    echo "$boot_type"
}

# Validate and ensure kernel module exists before loading
ensure_module() {
    local module="$1"
    [[ -z "$module" ]] && { log_error "ensure_module: No module name provided"; return 1; }

    if modprobe -n "$module" >/dev/null 2>&1; then
        log_debug "Module '$module' validation passed"
        return 0
    else
        log_error "Module '$module' does not exist or cannot be loaded"
        return 1
    fi
}

# Add module to modules-load.d if valid and not already present (idempotent)
add_module_persistent() {
    local module="$1"
    local config_file="${2:-/etc/modules-load.d/vfio.conf}"

    if ! ensure_module "$module"; then
        log_error "Cannot add invalid module '$module' to $config_file"
        return 1
    fi

    if [[ -f "$config_file" ]] && grep -q "^${module}$" "$config_file"; then
        log_debug "Module '$module' already in $config_file"
        return 0
    fi

    echo "$module" >> "$config_file"
    log_success "Added module '$module' to $config_file"

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

    if ! command -v pveversion >/dev/null 2>&1; then
        log_error "This script is designed for Proxmox VE systems"
        requirements_met=false
    else
        local pve_version
        pve_version=$(pveversion | head -1)
        log_info "Running on: $pve_version"
    fi

    if ! grep -qE "vmx|svm" /proc/cpuinfo; then
        log_error "CPU does not support virtualization (VT-x/AMD-V)"
        requirements_met=false
    else
        log_success "CPU virtualization support detected"
    fi

    case "$CPU_VENDOR" in
        "intel")
            if dmesg | grep -qiE "Intel-IOMMU|DMAR"; then
                log_success "Intel VT-d support detected"
            else
                log_warning "Intel VT-d may not be enabled in BIOS"
            fi
            ;;
        "amd")
            if dmesg | grep -qiE "AMD-Vi|IOMMU"; then
                log_success "AMD-Vi support detected"
            else
                log_warning "AMD-Vi may not be enabled in BIOS"
            fi
            ;;
    esac

    if ! lspci | grep -qE "VGA|3D|Display"; then
        log_error "No GPU devices found"
        requirements_met=false
    else
        log_success "GPU devices detected"
    fi

    if ! $requirements_met; then
        whiptail --title "Hardware Requirements" --msgbox \
            "Hardware requirements not met. Check the log for details:\n$LOG_FILE" 10 70
        return 1
    fi

    whiptail --title "Hardware Check" --msgbox \
        "Hardware requirements check completed successfully!" 8 60
    return 0
}

# Detect and catalog all GPUs (improved: class-code scan, SR-IOV awareness, robust parsing)
detect_gpus() {
    log_info "Scanning for GPU devices..."

    # Clear previous detection
    DETECTED_GPUS=()
    GPU_IOMMU_GROUPS=()
    GPU_DEVICE_IDS=()
    GPU_DRIVER_IN_USE=()
    GPU_IS_VF=()
    GPU_IS_PF=()
    GPU_SLOT=()
    GPU_CLASS=()
    GPU_PF_BDF=()

    local gpu_count=0
    local gpu_info=""

    # Display controller class codes: 0300 (VGA), 0302 (3D), 0380 (Display controller)
    while read -r bdf class vendor_device; do
        [[ -z "$bdf" ]] && continue

        bdf=$(normalize_bdf "$bdf") || continue
        local desc
        desc=$(get_pci_human_desc "$bdf")
        local iommu_group
        iommu_group=$(get_pci_iommu_group "$bdf")
        local driver
        driver=$(get_pci_driver_in_use "$bdf")
        local slot="${bdf%.*}"

        local is_vf="false"
        local is_pf="false"
        local pf_bdf=""

        if is_sriov_vf "$bdf"; then
            is_vf="true"
            pf_bdf=$(get_sriov_pf_bdf "$bdf")
        fi
        if is_sriov_pf "$bdf"; then
            is_pf="true"
        fi

        DETECTED_GPUS["$gpu_count"]="$bdf|$desc|$vendor_device"
        GPU_IOMMU_GROUPS["$gpu_count"]="$iommu_group"
        GPU_DEVICE_IDS["$gpu_count"]="$vendor_device"
        GPU_DRIVER_IN_USE["$gpu_count"]="$driver"
        GPU_IS_VF["$gpu_count"]="$is_vf"
        GPU_IS_PF["$gpu_count"]="$is_pf"
        GPU_SLOT["$gpu_count"]="$slot"
        GPU_CLASS["$gpu_count"]="${class%:}"
        GPU_PF_BDF["$gpu_count"]="$pf_bdf"

        gpu_info+="GPU $gpu_count: $bdf - $desc\n"
        gpu_info+="  Vendor:Device: $vendor_device | Class: ${class%:}\n"
        gpu_info+="  Driver: $driver\n"
        [[ -n "$iommu_group" ]] && gpu_info+="  IOMMU Group: $iommu_group\n"

        if [[ "$is_pf" == "true" ]]; then
            local totalvfs=0
            local numvfs=0
            totalvfs=$(cat "/sys/bus/pci/devices/$bdf/sriov_totalvfs" 2>/dev/null || echo 0)
            numvfs=$(cat "/sys/bus/pci/devices/$bdf/sriov_numvfs" 2>/dev/null || echo 0)
            gpu_info+="  SR-IOV: PF (totalvfs=$totalvfs, enabled=$numvfs)\n"
        elif [[ "$is_vf" == "true" ]]; then
            gpu_info+="  SR-IOV: VF (physfn=$pf_bdf)\n"
        fi

        gpu_info+="\n"
        ((gpu_count++))
    done < <(lspci -Dn 2>/dev/null | awk '$2 ~ /^03(00|02|80):/ {print $1, $2, $3}')

    if [[ $gpu_count -eq 0 ]]; then
        whiptail --title "GPU Detection" --msgbox "No GPU devices found!" 8 50
        return 1
    fi

    log_success "Detected $gpu_count GPU device(s)"

    whiptail --title "Detected GPUs" --scrolltext --msgbox \
        "Found $gpu_count GPU device(s):\n\n$gpu_info" 25 95

    return 0
}

# Check IOMMU groups and isolation (improved: detects non-GPU devices outside the GPU's own slot)
check_iommu_groups() {
    log_info "Analyzing IOMMU groups..."

    if [[ ! -d "/sys/kernel/iommu_groups" ]]; then
        whiptail --title "IOMMU Groups" --msgbox \
            "IOMMU is not active. Please enable IOMMU first." 8 60
        return 1
    fi

    local problematic_groups=""
    local summary=""

    for group_path in /sys/kernel/iommu_groups/*/; do
        [[ -d "$group_path" ]] || continue
        local group_num
        group_num=$(basename "$group_path")

        local devices=()
        local gpu_slots=()
        declare -A slot_is_gpu=()

        # Collect devices in group
        for device in "$group_path/devices/"*; do
            [[ -e "$device" ]] || continue
            local pci_id
            pci_id=$(basename "$device")
            devices+=("$pci_id")

            # Track GPU slots inside the group
            local class
            class=$(get_pci_class_code "$pci_id" 2>/dev/null || echo "")
            if [[ "$class" =~ ^03 ]]; then
                local slot="${pci_id%.*}"
                slot_is_gpu["$slot"]=1
            fi
        done

        # If group contains a GPU, check for extra devices not in GPU slot(s)
        local has_gpu=false
        for dev in "${devices[@]}"; do
            local class
            class=$(get_pci_class_code "$dev" 2>/dev/null || echo "")
            if [[ "$class" =~ ^03 ]]; then
                has_gpu=true
                break
            fi
        done

        if $has_gpu; then
            local outside=()
            for dev in "${devices[@]}"; do
                local slot="${dev%.*}"
                if [[ -z "${slot_is_gpu[$slot]:-}" ]]; then
                    outside+=("$dev")
                fi
            done

            if [[ ${#outside[@]} -gt 0 ]]; then
                problematic_groups+="Group $group_num: GPU mixed with other device(s) not in the GPU slot:\n"
                for dev in "${outside[@]}"; do
                    problematic_groups+="  - $(lspci -s "$dev")\n"
                done
                problematic_groups+="\n"
            fi
        fi
    done

    if [[ -n "$problematic_groups" ]]; then
        whiptail --title "IOMMU Analysis" --scrolltext --yesno \
            "WARNING: Some GPUs are not properly isolated:\n\n$problematic_groups\nThis may require ACS override (RISKY) or choosing a different GPU.\n\nContinue anyway?" 25 90
        return $?
    else
        whiptail --title "IOMMU Groups" --msgbox \
            "IOMMU Groups look OK.\n\nTip: If you still have VM startup issues, check if your GPU shares a group with non-GPU devices." 10 70
    fi

    return 0
}

# ---------------------------------------------------------
# IOMMU Configuration Functions
# ---------------------------------------------------------

configure_iommu() {
    log_info "Configuring IOMMU for $CPU_VENDOR CPU..."

    local iommu_params=""
    case "$CPU_VENDOR" in
        "intel") iommu_params="intel_iommu=on iommu=pt" ;;
        "amd")   iommu_params="amd_iommu=on iommu=pt" ;;
        *)       log_error "Unknown CPU vendor: $CPU_VENDOR"; return 1 ;;
    esac

    case "$BOOT_TYPE" in
        "systemd-boot") configure_systemd_boot_iommu "$iommu_params" ;;
        "grub-uefi"|"grub-legacy") configure_grub_iommu "$iommu_params" ;;
        *) log_error "Unknown boot type: $BOOT_TYPE"; return 1 ;;
    esac

    sed -i 's/IOMMU_CONFIGURED=false/IOMMU_CONFIGURED=true/' "$STATE_FILE" 2>/dev/null || true
    log_success "IOMMU configuration completed"

    return 0
}

configure_grub_iommu() {
    local params="$1"
    log_info "Configuring GRUB with IOMMU parameters: $params"

    local grub_file="/etc/default/grub"
    if [[ ! -f "$grub_file" ]]; then
        log_error "GRUB configuration file not found"
        return 1
    fi

    if ! command -v update-grub >/dev/null 2>&1; then
        log_error "update-grub not found (is GRUB installed?)"
        return 1
    fi

    cp "$grub_file" "$BACKUP_DIR/grub.bak.$(date +%Y%m%d_%H%M%S)"

    # Ensure the key exists
    if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_file"; then
        echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' >> "$grub_file"
    fi

    # Extract current cmdline
    local current
    current="$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)".*/\1/p' "$grub_file" | head -n1)"

    local updated="$current"
    local changed=false

    # Add only missing params (by base)
    local p base
    for p in $params; do
        base="${p%%=*}"
        if cmdline_has_param "$updated" "$base"; then
            # If base exists but value differs, log a warning (don't auto-rewrite)
            local esc_p
            esc_p="$(escape_ere "$p")"
            if ! grep -qE "(^|[[:space:]])${esc_p}([[:space:]]|$)" <<<"$updated"; then
                log_warning "GRUB already has '$base' but with a different value than '$p' (leaving as-is)"
            fi
        else
            updated="$updated $p"
            changed=true
        fi
    done

    # Normalize spaces
    updated="$(echo "$updated" | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"

    if ! $changed; then
        log_warning "IOMMU parameters already present in GRUB (no changes)"
        return 0
    fi

    local repl
    repl="$(escape_sed_repl "$updated")"
    sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"${repl}\"/" "$grub_file"

    if update-grub 2>/dev/null; then
        log_success "GRUB updated successfully"
    else
        log_error "Failed to update GRUB"
        return 1
    fi

    return 0
}

configure_systemd_boot_iommu() {
    local params="$1"
    log_info "Configuring systemd-boot with IOMMU parameters: $params"

    local cmdline_file="/etc/kernel/cmdline"

    if [[ ! -f "$cmdline_file" ]]; then
        log_warning "systemd-boot cmdline file not found at $cmdline_file - creating"
        mkdir -p /etc/kernel
        create_cmdline_from_proc > "$cmdline_file"
    fi

    cp "$cmdline_file" "$BACKUP_DIR/cmdline.bak.$(date +%Y%m%d_%H%M%S)"

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

    local current_cmdline
    current_cmdline=$(cat "$cmdline_file")
    echo "$current_cmdline $params" | sed 's/  */ /g; s/^ //; s/ $//' > "$cmdline_file"
    log_info "Updated $cmdline_file"

    local refresh_success=false
    if command -v proxmox-boot-tool >/dev/null 2>&1; then
        log_info "Running proxmox-boot-tool refresh..."
        if proxmox-boot-tool refresh 2>&1 | tee -a "$LOG_FILE"; then
            refresh_success=true
            log_success "systemd-boot updated with proxmox-boot-tool"
        else
            log_warning "proxmox-boot-tool refresh failed, trying reinit..."
            if proxmox-boot-tool reinit 2>&1 | tee -a "$LOG_FILE"; then
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
        log_error "Failed to update systemd-boot - cmdline updated but boot entries may be stale"
        whiptail --title "Boot Update Warning" --msgbox \
            "Kernel parameters were written to $cmdline_file\nbut boot entry refresh failed.\n\nYou may need to run manually:\nproxmox-boot-tool refresh\n\nOr check if ESP is mounted correctly." 12 70
        return 1
    fi

    return 0
}

add_kernel_parameter() {
    local param="$1"
    local description="$2"

    log_info "Adding kernel parameter: $param ($description)"

    case "$BOOT_TYPE" in
        "systemd-boot")
            local cmdline_file="/etc/kernel/cmdline"
            if [[ ! -f "$cmdline_file" ]]; then
                log_warning "Cmdline file not found at $cmdline_file - creating from /proc/cmdline"
                mkdir -p /etc/kernel
                create_cmdline_from_proc > "$cmdline_file"
            fi

            local param_base="${param%%=*}"
            local current_cmdline
            current_cmdline="$(cat "$cmdline_file")"

            if cmdline_has_param "$current_cmdline" "$param_base"; then
                log_warning "Parameter '$param_base' already exists in cmdline"
                return 0
            fi

            cp "$cmdline_file" "$BACKUP_DIR/cmdline.param.$(date +%Y%m%d_%H%M%S)"

            echo "$current_cmdline $param" | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//' > "$cmdline_file"

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
            [[ -f "$grub_file" ]] || { log_error "GRUB config file not found: $grub_file"; return 1; }

            if ! command -v update-grub >/dev/null 2>&1; then
                log_error "update-grub not found (is GRUB installed?)"
                return 1
            fi

            cp "$grub_file" "$BACKUP_DIR/grub.param.$(date +%Y%m%d_%H%M%S)"

            if ! grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file"; then
                echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' >> "$grub_file"
            fi

            local param_base="${param%%=*}"
            local current
            current="$(sed -n 's/^GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)".*/\1/p' "$grub_file" | head -n1)"

            if cmdline_has_param "$current" "$param_base"; then
                log_warning "Parameter '$param_base' already exists in GRUB config"
                return 0
            fi

            local updated
            updated="$(echo "$current $param" | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"

            local repl
            repl="$(escape_sed_repl "$updated")"
            sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"${repl}\"/" "$grub_file"

            if update-grub 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Added $param to GRUB"
            else
                log_error "Failed to update GRUB"
                return 1
            fi
            ;;
    esac
}

configure_additional_parameters() {
    local choice
    choice=$(whiptail --title "Additional Kernel Parameters" --menu \
        "Select additional parameters to configure:" 15 90 7 \
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
                "pcie_acs_override reduces security by bypassing IOMMU isolation.\nOnly use if your hardware has problematic IOMMU groups.\nContinue?" 10 75; then
                add_kernel_parameter "pcie_acs_override=downstream" "ACS override"
            fi
            ;;
        4) add_kernel_parameter "vfio-pci.disable_vga=1" "VFIO VGA disable" ;;
        5) add_kernel_parameter "kvm.ignore_msrs=1" "KVM MSR ignore" ;;
        6) log_info "Skipping additional parameters" ;;
        7)
            local custom_param
            custom_param=$(whiptail --inputbox "Enter custom kernel parameter:" 8 70 3>&1 1>&2 2>&3)
            if [[ -n "$custom_param" ]]; then
                add_kernel_parameter "$custom_param" "Custom parameter"
            fi
            ;;
    esac
}

# ---------------------------------------------------------
# VFIO and Module Configuration Functions
# ---------------------------------------------------------

configure_vfio_modules() {
    log_info "Configuring VFIO modules..."

    local vfio_conf="/etc/modules-load.d/vfio.conf"
    local all_modules_valid=true

    cat > "$vfio_conf" << EOF
# VFIO modules for GPU passthrough
# Generated by PECU on $(date)
EOF

    log_info "Validating VFIO kernel modules..."
    for module in "${VFIO_MODULES[@]}"; do
        if ! add_module_persistent "$module" "$vfio_conf"; then
            log_error "Failed to validate/add module: $module"
            all_modules_valid=false
        fi
    done

    if ! $all_modules_valid; then
        log_error "Some VFIO modules failed validation"
        whiptail --title "Module Validation Error" --msgbox \
            "Some VFIO modules could not be validated.\n\nCheck $LOG_FILE for details." 10 70
        return 1
    fi

    sed -i 's/VFIO_CONFIGURED=false/VFIO_CONFIGURED=true/' "$STATE_FILE" 2>/dev/null || true
    log_success "VFIO modules configured and validated successfully"

    return 0
}

blacklist_gpu_drivers() {
    log_info "Configuring GPU driver blacklist..."

    if [[ -f "/etc/modprobe.d/blacklist.conf" ]]; then
        cp /etc/modprobe.d/blacklist.conf "$BACKUP_DIR/blacklist.conf.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    local choice
    choice=$(whiptail --title "GPU Driver Blacklist" --menu \
        "Select which GPU drivers to blacklist:" 15 80 6 \
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

    if [[ "$choice" != "6" ]]; then
        log_info "Updating initramfs..."
        if update-initramfs -u -k all; then
            log_success "initramfs updated successfully"
            sed -i 's/GPU_BLACKLISTED=false/GPU_BLACKLISTED=true/' "$STATE_FILE" 2>/dev/null || true
        else
            log_error "Failed to update initramfs"
            whiptail --title "Error" --msgbox \
                "Failed to update initramfs. Check logs for details:\n$LOG_FILE" 9 70
            return 1
        fi
    fi

    return 0
}

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

blacklist_intel_drivers() {
    log_info "Blacklisting Intel drivers..."

    cat > "$BLACKLIST_CONFIG" << EOF
# Intel GPU driver blacklist
# Generated by PECU on $(date)
blacklist i915
EOF

    log_success "Intel drivers blacklisted"
}

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

blacklist_custom_drivers() {
    local modules
    modules=$(whiptail --inputbox "Enter module names to blacklist (space-separated):" 8 70 3>&1 1>&2 2>&3)

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

# Configure VFIO device IDs (FIXED: surgical per-slot binding, SR-IOV VF filtering, vfio.conf validation)
configure_vfio_device_ids() {
    log_info "Configuring VFIO device IDs..."

    if [[ ${#DETECTED_GPUS[@]} -eq 0 ]]; then
        log_warning "No GPUs detected yet - running GPU detection."
        detect_gpus || return 1
    fi

    local include_vfs=false
    if whiptail --title "SR-IOV / vGPU" --yesno \
        "Include SR-IOV Virtual Functions (vGPUs/VFs) in the selection list?\n\nRecommended: NO (prevents the dGPU list from being hidden by many VFs)." 12 80; then
        include_vfs=true
    fi

    local items=()
    local visible_count=0

    for i in $(printf '%s\n' "${!DETECTED_GPUS[@]}" | sort -n); do
        local info="${DETECTED_GPUS[$i]}"
        local bdf
        bdf=$(echo "$info" | cut -d'|' -f1)
        local desc
        desc=$(echo "$info" | cut -d'|' -f2)
        local id
        id=$(echo "$info" | cut -d'|' -f3)

        local grp="${GPU_IOMMU_GROUPS[$i]}"
        local drv="${GPU_DRIVER_IN_USE[$i]}"
        local is_vf="${GPU_IS_VF[$i]}"
        local is_pf="${GPU_IS_PF[$i]}"

        if [[ "$is_vf" == "true" ]] && ! $include_vfs; then
            continue
        fi

        local extra=""
        if [[ "$is_vf" == "true" ]]; then
            extra=" [SR-IOV VF]"
        elif [[ "$is_pf" == "true" ]]; then
            local numvfs=0
            numvfs=$(cat "/sys/bus/pci/devices/$bdf/sriov_numvfs" 2>/dev/null || echo 0)
            extra=" [SR-IOV PF: ${numvfs} VFs enabled]"
        fi

        local label="$bdf - $desc ($id) [group:${grp:-N/A}] [driver:${drv}]$extra"
        items+=("$i" "$label" "OFF")
        ((visible_count++))
    done

    if [[ $visible_count -eq 0 ]]; then
        whiptail --title "VFIO Binding" --msgbox \
            "No GPU devices available for selection.\n\nTip: If you only see SR-IOV VFs, choose NO on the VF prompt." 10 70
        return 1
    fi

    local selected
    selected=$(whiptail --title "Select GPUs for VFIO" --separate-output --checklist \
        "Choose GPU(s) to configure for passthrough.\n\nPECU will bind ONLY the selected GPU's PCI *slot functions* (e.g. .0/.1/.2) to vfio-pci.\nIt will NOT bind the whole IOMMU group (prevents Phoenix APU mis-binding)." \
        25 110 14 \
        "${items[@]}" 3>&1 1>&2 2>&3) || {
            log_warning "No selection made (cancelled)."
            return 0
        }

    mapfile -t selected_gpus <<< "$selected"

    if [[ ${#selected_gpus[@]} -eq 0 ]]; then
        log_warning "No GPUs selected for VFIO configuration"
        return 0
    fi

    local use_disable_idle_d3=false
    if whiptail --title "Prevent GPU Sleep (D3)" --yesno \
        "Apply 'disable_idle_d3=1' to vfio-pci?\n\nThis can help with GPUs that go to sleep / D3 and fail in passthrough.\n(Useful for some dGPU sleep issues.)\n\nEnable it?" 12 80; then
        use_disable_idle_d3=true
    fi

    # Build a surgical list of PCI BDFs to bind: GPU slot functions only.
    declare -A seen_bdfs=()
    local bdfs_to_bind=()
    local warnings=""

    for idx in "${selected_gpus[@]}"; do
        idx="${idx//$'\r'/}"
        local info="${DETECTED_GPUS[$idx]}"
        local bdf
        bdf=$(echo "$info" | cut -d'|' -f1)
        bdf=$(normalize_bdf "$bdf") || continue

        local is_vf="${GPU_IS_VF[$idx]}"
        local grp="${GPU_IOMMU_GROUPS[$idx]}"

        # Phoenix/iGPU mixed-group warning (but we still only bind the GPU slot functions)
        if [[ -n "$grp" ]]; then
            local dev_count=0
            dev_count=$(find "/sys/kernel/iommu_groups/$grp/devices" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
            if [[ "$dev_count" -ge 8 ]]; then
                warnings+="• Selected GPU $bdf is in IOMMU group $grp with $dev_count devices.\n  PECU will ONLY bind the GPU slot functions, not all group devices.\n\n"
            fi
        fi

        if [[ "$is_vf" == "true" ]]; then
            # Bind only the VF itself
            if [[ -z "${seen_bdfs[$bdf]:-}" ]]; then
                bdfs_to_bind+=("$bdf")
                seen_bdfs["$bdf"]=1
            fi
            continue
        fi

        # Non-VF: bind all functions in the same slot (0000:BB:DD.*)
        local slot="${bdf%.*}"
        for devpath in /sys/bus/pci/devices/${slot}.*; do
            [[ -e "$devpath" ]] || continue
            local dev_bdf
            dev_bdf=$(basename "$devpath")

            # Do NOT bind SR-IOV VFs (prevents grabbing vGPU VFs by mistake)
            if is_sriov_vf "$dev_bdf"; then
                continue
            fi

            if [[ -z "${seen_bdfs[$dev_bdf]:-}" ]]; then
                bdfs_to_bind+=("$dev_bdf")
                seen_bdfs["$dev_bdf"]=1
            fi
        done
    done

    if [[ ${#bdfs_to_bind[@]} -eq 0 ]]; then
        log_error "No PCI devices selected for binding"
        return 1
    fi

    # Convert BDF list to unique vendor:device IDs
    declare -A seen_ids=()
    local ids_list=()
    local bdf_report=""

    for dev_bdf in "${bdfs_to_bind[@]}"; do
        local id
        id=$(get_pci_vendor_device "$dev_bdf" 2>/dev/null || echo "")
        if ! is_valid_vendor_device "$id"; then
            log_warning "Skipping invalid vendor:device for $dev_bdf: '$id'"
            continue
        fi

        if [[ -z "${seen_ids[$id]:-}" ]]; then
            seen_ids["$id"]=1
            ids_list+=("$id")
        fi

        bdf_report+="$dev_bdf  [$id]  $(get_pci_human_desc "$dev_bdf")\n"
    done

    if [[ ${#ids_list[@]} -eq 0 ]]; then
        log_error "Failed to extract vendor:device IDs"
        return 1
    fi

    local ids_csv
    ids_csv=$(IFS=, ; echo "${ids_list[*]}")

    # Preview: which devices in the host match these IDs?
    local match_report=""
    for id in "${ids_list[@]}"; do
        local matches
        matches=$(lspci -Dn -d "$id" 2>/dev/null | awk '{print $1}' | sort -u)
        if [[ -n "$matches" ]]; then
            while read -r m; do
                [[ -z "$m" ]] && continue
                match_report+="$m  [$id]  $(get_pci_human_desc "$m")\n"
            done <<< "$matches"
        fi
    done

    local preview="PECU will bind these PCI devices (slot functions only):\n\n$bdf_report\n"
    preview+="VFIO ids=[$ids_csv]\n\n"
    preview+="IMPORTANT: ids= binds ALL devices on the host that share these vendor:device IDs.\n"
    preview+="If you have multiple identical GPUs or many SR-IOV VFs with the same ID, consider address-based binding (advanced).\n\n"
    preview+="Devices in this host that currently match the selected IDs:\n\n$match_report\n"
    [[ -n "$warnings" ]] && preview+="Warnings:\n$warnings\n"
    preview+="\nWrite to $VFIO_CONFIG ?"

    if ! whiptail --title "VFIO Binding Preview" --scrolltext --yesno "$preview" 30 110; then
        log_info "User cancelled VFIO binding"
        return 0
    fi

    # Backup existing vfio.conf
    if [[ -f "$VFIO_CONFIG" ]]; then
        cp "$VFIO_CONFIG" "$BACKUP_DIR/$(basename "$VFIO_CONFIG").bak.$(date +%Y%m%d_%H%M%S)"
    fi

    local extra_opts="disable_vga=1"
    $use_disable_idle_d3 && extra_opts="$extra_opts disable_idle_d3=1"

    cat > "$VFIO_CONFIG" << EOF
# VFIO GPU configuration
# Generated by PECU on $(date)
# Notes:
# - This file must contain 'options' lines. Bare PCI IDs will break modprobe parsing.
# - PECU writes a single, validated vfio-pci options line to avoid "bad line" errors.
options vfio-pci ids=$ids_csv $extra_opts
EOF
    chmod 644 "$VFIO_CONFIG"

    if ! validate_vfio_conf "$VFIO_CONFIG"; then
        whiptail --title "VFIO Config Error" --msgbox \
            "vfio.conf validation failed.\nPECU created a backup in:\n$BACKUP_DIR\n\nCheck:\n$VFIO_CONFIG\n\nLog:\n$LOG_FILE" 14 75
        return 1
    fi

    log_success "VFIO device IDs configured: $ids_csv"

    if whiptail --title "Initramfs Update" --yesno \
        "Update initramfs now?\n\nRecommended after changing VFIO config.\nRun: update-initramfs -u -k all" 12 70; then
        log_info "Updating initramfs..."
        if update-initramfs -u -k all 2>&1 | tee -a "$LOG_FILE"; then
            log_success "initramfs updated successfully"
        else
            log_error "Failed to update initramfs"
            whiptail --title "Initramfs Error" --msgbox \
                "update-initramfs failed. Check $LOG_FILE for details." 8 60
            return 1
        fi
    fi

    return 0
}

configure_kvm_options() {
    log_info "Configuring KVM options for better GPU compatibility..."

    cat > "$KVM_CONFIG" << EOF
# KVM configuration for GPU passthrough
# Generated by PECU on $(date)
# Ignore MSR access for better NVIDIA compatibility (common workaround)
options kvm ignore_msrs=1 report_ignored_msrs=0
EOF

    local enable_unsafe=false
    if whiptail --title "VFIO Interrupt Remapping (Security)" --yesno \
        "Enable 'allow_unsafe_interrupts=1' for vfio_iommu_type1?\n\nThis REDUCES security (weaker interrupt isolation).\nOnly enable if you see errors about interrupt remapping / legacy interrupts.\n\nEnable it?" 14 78; then
        enable_unsafe=true
    fi

    if $enable_unsafe; then
        cat > "$VFIO_IOMMU_CONFIG" << EOF
# VFIO IOMMU Type1 configuration for GPU passthrough
# Generated by PECU on $(date)
# WARNING: This reduces isolation/security. Enable only if required.
options vfio_iommu_type1 allow_unsafe_interrupts=1
EOF
        log_warning "allow_unsafe_interrupts enabled (reduced security)"
    else
        cat > "$VFIO_IOMMU_CONFIG" << EOF
# VFIO IOMMU Type1 configuration for GPU passthrough
# Generated by PECU on $(date)
# NOTE: allow_unsafe_interrupts is intentionally NOT enabled by default.
# Uncomment ONLY if you know you need it:
# options vfio_iommu_type1 allow_unsafe_interrupts=1
EOF
        log_info "allow_unsafe_interrupts left disabled (recommended)"
    fi

    log_success "KVM and VFIO options configured"
    return 0
}

# ---------------------------------------------------------
# Repository Management Functions (Idempotent)
# ---------------------------------------------------------

add_repo_line() {
    local file_path="$1"
    local repo_line="$2"
    local description="${3:-repository entry}"

    if [[ -z "$file_path" ]] || [[ -z "$repo_line" ]]; then
        log_error "add_repo_line: file_path and repo_line required"
        return 1
    fi

    local dir_path
    dir_path=$(dirname "$file_path")
    [[ -d "$dir_path" ]] || mkdir -p "$dir_path" || { log_error "Failed to create directory: $dir_path"; return 1; }

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

    if grep -qxF "$repo_line" "$file_path"; then
        log_debug "Repository line already present: $repo_line"
        return 0
    fi

    local repo_url
    repo_url=$(echo "$repo_line" | awk '{print $2}')
    if [[ -n "$repo_url" ]] && grep -qF "$repo_url" "$file_path"; then
        log_warning "Similar repository URL already exists in $file_path: $repo_url"
        log_warning "Existing line differs in format - not adding duplicate"
        return 0
    fi

    echo "$repo_line" >> "$file_path"
    log_success "Added $description: $repo_line"

    return 0
}

remove_pecu_repos() {
    local file_path="$1"

    [[ -f "$file_path" ]] || { log_debug "File does not exist, nothing to remove: $file_path"; return 0; }

    if ! grep -q "^# PECU-MANAGED:" "$file_path"; then
        log_warning "File is not PECU-managed, skipping: $file_path"
        return 0
    fi

    cp "$file_path" "$BACKUP_DIR/$(basename "$file_path").removed.$(date +%Y%m%d_%H%M%S)"
    rm -f "$file_path"
    log_success "Removed PECU-managed repository file: $file_path"

    return 0
}

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

get_debian_codename() {
    local pve_version=""
    if command -v pveversion >/dev/null 2>&1; then
        pve_version=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1 2>/dev/null)
    fi

    case "$pve_version" in
        7) echo "bullseye" ;;
        8) echo "bookworm" ;;
        9) echo "trixie" ;;
        *)
            if [[ -f /etc/os-release ]]; then
                # shellcheck disable=SC1091
                source /etc/os-release
                echo "${VERSION_CODENAME:-bookworm}"
            else
                echo "bookworm"
            fi
            ;;
    esac
}

# ---------------------------------------------------------
# Advanced Configuration Functions
# ---------------------------------------------------------

install_vendor_reset() {
    log_info "Installing vendor-reset for AMD GPU reset bug fix..."

    if ! whiptail --title "Install vendor-reset" --yesno \
        "vendor-reset can help fix AMD GPU reset issues in VMs.\n\nNOTE: It does NOT work for every AMD GPU.\n\nContinue?" 12 70; then
        return 0
    fi

    log_info "Checking network connectivity..."
    if ! http_get "https://github.com" >/dev/null; then
        log_error "No network connectivity to GitHub"
        whiptail --title "Network Error" --msgbox \
            "Cannot reach GitHub. Please check your internet connection." 8 60
        return 1
    fi

    # Proxmox kernels use pve-headers-$(uname -r)
    local headers_pkg=""
    local krn
    krn=$(uname -r)

    if apt-cache show "pve-headers-$krn" >/dev/null 2>&1; then
        headers_pkg="pve-headers-$krn"
    elif apt-cache show "linux-headers-$krn" >/dev/null 2>&1; then
        headers_pkg="linux-headers-$krn"
    else
        headers_pkg="pve-headers-$krn"
        log_warning "Kernel headers package not found in apt-cache for $krn. Build may fail."
    fi

    log_info "Installing build dependencies..."
    if ! apt update; then
        log_error "Failed to update package lists"
        return 1
    fi

    if ! apt install -y dkms build-essential git "$headers_pkg"; then
        log_error "Failed to install dependencies (dkms/build-essential/git/headers)"
        return 1
    fi

    local temp_dir="/tmp/vendor-reset"
    rm -rf "$temp_dir"

    log_info "Downloading vendor-reset..."
    if ! git clone https://github.com/gnif/vendor-reset.git "$temp_dir"; then
        log_error "Failed to clone vendor-reset repository"
        return 1
    fi

    cd "$temp_dir" || return 1

    log_info "Building and installing vendor-reset via DKMS..."
    local ver
    ver=$(cat VERSION 2>/dev/null || echo "")

    # Remove any existing version to avoid DKMS conflicts
    if dkms status | grep -qi "vendor-reset"; then
        log_info "Removing existing vendor-reset DKMS module..."
        dkms remove vendor-reset --all 2>/dev/null || true
    fi

    if dkms add . && dkms install "vendor-reset/${ver}"; then
        log_success "vendor-reset installed successfully"

        # Ensure module loads at boot
        mkdir -p /etc/modules-load.d
        echo "vendor_reset" > /etc/modules-load.d/vendor-reset.conf

        # Update initramfs so module is available early
        update-initramfs -u -k all 2>&1 | tee -a "$LOG_FILE" || log_warning "initramfs update had warnings/errors"

        cd - > /dev/null
        rm -rf "$temp_dir"

        whiptail --title "vendor-reset" --msgbox \
            "vendor-reset installed successfully!\n\nIt will be loaded on next reboot.\n\nReminder: Some GPUs still won't reset reliably even with vendor-reset." 12 70
        return 0
    else
        log_error "Failed to build/install vendor-reset"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
}

configure_sources_list() {
    log_info "Configuring APT sources (idempotent mode)..."

    local debian_codename
    debian_codename=$(get_debian_codename)

    local pve_version="unknown"
    if command -v pveversion >/dev/null 2>&1; then
        pve_version=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1 2>/dev/null)
    fi

    log_info "Detected Proxmox VE $pve_version (Debian $debian_codename)"

    local backup_marker="$BACKUP_DIR/.sources_backed_up_$(date +%Y%m%d)"
    if [[ ! -f "$backup_marker" ]] && [[ -f /etc/apt/sources.list ]]; then
        cp /etc/apt/sources.list "$BACKUP_DIR/sources.list.bak.$(date +%Y%m%d_%H%M%S)"
        touch "$backup_marker"
        log_info "Backed up /etc/apt/sources.list"
    fi

    local pecu_sources_file="/etc/apt/sources.list.d/pecu-repos.list"
    local repos_added=0

    # Debian 12+ split non-free-firmware; include it to avoid microcode/firmware install failures
    local components="main contrib"
    case "$debian_codename" in
        bullseye) components="main contrib non-free" ;;
        bookworm|trixie|forky) components="main contrib non-free non-free-firmware" ;;
        *) components="main contrib non-free non-free-firmware" ;;
    esac

    local debian_main="deb http://deb.debian.org/debian $debian_codename $components"
    local debian_updates="deb http://deb.debian.org/debian $debian_codename-updates $components"
    local debian_security="deb http://security.debian.org/debian-security $debian_codename-security $components"

    log_info "Adding Debian repositories to $pecu_sources_file..."

    add_repo_line "$pecu_sources_file" "$debian_main" "Debian main repository" && ((repos_added++))
    add_repo_line "$pecu_sources_file" "$debian_updates" "Debian updates repository" && ((repos_added++))
    add_repo_line "$pecu_sources_file" "$debian_security" "Debian security repository" && ((repos_added++))

    if whiptail --title "Proxmox Repository" --yesno \
        "Add Proxmox no-subscription repository?\n\nRecommended for home labs and testing.\n\nAdd repository?" 12 70; then

        local pve_repo="deb http://download.proxmox.com/debian/pve $debian_codename pve-no-subscription"
        add_repo_line "$pecu_sources_file" "$pve_repo" "Proxmox no-subscription repository" && ((repos_added++))
    else
        log_info "Skipping Proxmox no-subscription repository"
    fi

    if [[ $repos_added -gt 0 ]]; then
        log_success "Repository configuration complete (managed file: $pecu_sources_file)"

        if whiptail --title "Update Package Lists" --yesno \
            "Repository configuration updated.\n\nRun 'apt update' now?" 10 60; then
            log_info "Updating APT package lists..."
            apt update 2>&1 | tee -a "$LOG_FILE" || log_warning "apt update had warnings/errors"
        fi
    else
        log_info "All repositories already configured - no changes needed"
    fi

    return 0
}

show_repo_status() {
    log_info "Checking current repository configuration..."

    local debian_codename
    debian_codename=$(get_debian_codename)

    local pve_version="N/A"
    if command -v pveversion >/dev/null 2>&1; then
        pve_version=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1 2>/dev/null)
    fi

    local status_report=""
    status_report+="═══════════════════════════════════════════════════════\n"
    status_report+="           REPOSITORY CONFIGURATION STATUS\n"
    status_report+="═══════════════════════════════════════════════════════\n\n"
    status_report+="System Information:\n"
    status_report+="  Proxmox VE: $pve_version\n"
    status_report+="  Debian Codename: $debian_codename\n\n"

    local pecu_sources="/etc/apt/sources.list.d/pecu-repos.list"
    status_report+="PECU-Managed Repositories:\n"
    status_report+="────────────────────────────────────────────────────\n"

    if [[ -f "$pecu_sources" ]]; then
        local repo_count
        repo_count=$(grep -c "^deb " "$pecu_sources" 2>/dev/null || echo 0)
        status_report+="  File: $pecu_sources\n"
        status_report+="  Status: ✓ Configured\n"
        status_report+="  Repositories: $repo_count\n\n"
        status_report+="  Configured entries:\n"
        while IFS= read -r line; do
            [[ "$line" =~ ^deb ]] && status_report+="    • $line\n"
        done < "$pecu_sources"
    else
        status_report+="  Status: ✗ Not configured\n"
        status_report+="  File: $pecu_sources (does not exist)\n"
    fi

    status_report+="\n═══════════════════════════════════════════════════════\n"

    echo -e "$status_report" | tee -a "$LOG_FILE"

    whiptail --title "Repository Status" --scrolltext --msgbox \
        "$status_report" 25 70

    return 0
}

preview_repo_changes() {
    log_info "Generating repository configuration preview..."

    local debian_codename
    debian_codename=$(get_debian_codename)
    local pecu_sources_file="/etc/apt/sources.list.d/pecu-repos.list"

    local components="main contrib"
    case "$debian_codename" in
        bullseye) components="main contrib non-free" ;;
        bookworm|trixie|forky) components="main contrib non-free non-free-firmware" ;;
        *) components="main contrib non-free non-free-firmware" ;;
    esac

    local preview=""
    preview+="═══════════════════════════════════════════════════════\n"
    preview+="        REPOSITORY CONFIGURATION PREVIEW\n"
    preview+="                  (DRY-RUN MODE)\n"
    preview+="═══════════════════════════════════════════════════════\n\n"
    preview+="Target Debian: $debian_codename\n"
    preview+="Target File: $pecu_sources_file\n\n"
    preview+="Planned Changes:\n"
    preview+="────────────────────────────────────────────────────\n"

    local debian_main="deb http://deb.debian.org/debian $debian_codename $components"
    local debian_updates="deb http://deb.debian.org/debian $debian_codename-updates $components"
    local debian_security="deb http://security.debian.org/debian-security $debian_codename-security $components"
    local pve_repo="deb http://download.proxmox.com/debian/pve $debian_codename pve-no-subscription"

    preview+="$(show_repo_change "$pecu_sources_file" "$debian_main" "Debian main")\n"
    preview+="$(show_repo_change "$pecu_sources_file" "$debian_updates" "Debian updates")\n"
    preview+="$(show_repo_change "$pecu_sources_file" "$debian_security" "Debian security")\n"
    preview+="$(show_repo_change "$pecu_sources_file" "$pve_repo" "Proxmox no-subscription")\n"

    preview+="\nLegend:\n"
    preview+="  [NEW FILE] - File will be created\n"
    preview+="  [ADD]      - Line will be added\n"
    preview+="  [EXISTS]   - Already configured (no change)\n"
    preview+="\n═══════════════════════════════════════════════════════\n"
    preview+="Note: This is a preview only. No changes will be made.\n"
    preview+="═══════════════════════════════════════════════════════\n"

    echo -e "$preview" | tee -a "$LOG_FILE"

    whiptail --title "Repository Preview (Dry-Run)" --scrolltext --msgbox \
        "$preview" 25 70

    return 0
}

install_dependencies() {
    log_info "Installing essential packages for GPU passthrough..."

    local packages=(
        "pciutils"
        "lshw"
        "dkms"
        "build-essential"
    )

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

check_passthrough_status() {
    log_info "Checking current GPU passthrough status..."

    local status_info=""

    if [[ -d /sys/kernel/iommu_groups ]] && dmesg | grep -qiE "IOMMU|DMAR|AMD-Vi"; then
        local iommu_groups
        iommu_groups=$(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
        status_info+="+ IOMMU: Enabled ($iommu_groups groups)\n"
    else
        status_info+="- IOMMU: Disabled or incomplete\n"
    fi

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

    if [[ -f "$BLACKLIST_CONFIG" ]] && [[ -s "$BLACKLIST_CONFIG" ]]; then
        status_info+="+ GPU Drivers: Blacklisted\n"
    else
        status_info+="- GPU Drivers: Not blacklisted\n"
    fi

    if [[ -f "$VFIO_CONFIG" ]] && [[ -s "$VFIO_CONFIG" ]]; then
        status_info+="+ VFIO Devices: Configured\n"
        if ! validate_vfio_conf "$VFIO_CONFIG"; then
            status_info+="  ⚠ vfio.conf: INVALID (run Repair VFIO Config)\n"
        fi
    else
        status_info+="- VFIO Devices: Not configured\n"
    fi

    local bound_devices
    bound_devices=$(find /sys/bus/pci/drivers/vfio-pci -name "0000:*" 2>/dev/null | wc -l)
    status_info+="  VFIO-bound devices: $bound_devices\n"

    local cmdline
    cmdline=$(cat /proc/cmdline 2>/dev/null || echo "")
    if echo "$cmdline" | grep -q "iommu=\|intel_iommu=\|amd_iommu="; then
        status_info+="+ Kernel parameters: Configured\n"
    else
        status_info+="- Kernel parameters: Missing\n"
    fi

    whiptail --title "GPU Passthrough Status" --msgbox \
        "Current GPU Passthrough Configuration:\n\n$status_info\nLegend: + = OK, - = Issue" 22 75

    return 0
}

verify_configuration_live() {
    log_info "Running live configuration verification..."

    local verification_failed=false
    local verification_report=""
    local current_cmdline
    current_cmdline=$(cat /proc/cmdline 2>/dev/null)

    verification_report+="═══════════════════════════════════════════════════════\n"
    verification_report+="           LIVE CONFIGURATION VERIFICATION\n"
    verification_report+="═══════════════════════════════════════════════════════\n\n"

    verification_report+="[1] Kernel Parameters (from /proc/cmdline):\n"
    verification_report+="────────────────────────────────────────────────────\n"

    local required_params=()
    case "$CPU_VENDOR" in
        "intel") required_params=("intel_iommu=on" "iommu=pt") ;;
        "amd") required_params=("amd_iommu=on" "iommu=pt") ;;
    esac

    for param in "${required_params[@]}"; do
        if echo "$current_cmdline" | grep -qE "(^| )${param}( |$)"; then
            verification_report+="  ✓ $param: ACTIVE\n"
        else
            verification_report+="  ✗ $param: MISSING\n"
            verification_failed=true
        fi
    done
    verification_report+="\n"

    verification_report+="[2] VFIO Kernel Modules (from lsmod):\n"
    verification_report+="────────────────────────────────────────────────────\n"
    for module in "${VFIO_MODULES[@]}"; do
        if lsmod | grep -q "^${module}"; then
            verification_report+="  ✓ $module: LOADED\n"
        else
            verification_report+="  ✗ $module: NOT LOADED\n"
            verification_failed=true
        fi
    done
    verification_report+="\n"

    verification_report+="[3] Configuration Files:\n"
    verification_report+="────────────────────────────────────────────────────\n"

    local cmdline_file=""
    case "$BOOT_TYPE" in
        "systemd-boot") cmdline_file="/etc/kernel/cmdline" ;;
        "grub-"*) cmdline_file="/etc/default/grub" ;;
    esac

    if [[ -f "$cmdline_file" ]] && [[ -s "$cmdline_file" ]]; then
        verification_report+="  ✓ Bootloader config: $cmdline_file\n"
    else
        verification_report+="  ✗ Bootloader config: Missing or empty\n"
        verification_failed=true
    fi

    if [[ -f "/etc/modules-load.d/vfio.conf" ]] && [[ -s "/etc/modules-load.d/vfio.conf" ]]; then
        verification_report+="  ✓ Module autoload: /etc/modules-load.d/vfio.conf\n"
    else
        verification_report+="  ✗ Module autoload: Missing or empty\n"
        verification_failed=true
    fi

    if [[ -f "$VFIO_CONFIG" ]]; then
        if validate_vfio_conf "$VFIO_CONFIG"; then
            verification_report+="  ✓ VFIO device config: $VFIO_CONFIG (valid)\n"
        else
            verification_report+="  ✗ VFIO device config: $VFIO_CONFIG (INVALID)\n"
            verification_failed=true
        fi
    else
        verification_report+="  ⚠ VFIO device config: Not yet configured\n"
    fi

    verification_report+="\n"

    verification_report+="[4] IOMMU Status:\n"
    verification_report+="────────────────────────────────────────────────────\n"
    if [[ -d "/sys/kernel/iommu_groups" ]]; then
        local group_count
        group_count=$(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        verification_report+="  ✓ IOMMU groups: $group_count found\n"
    else
        verification_report+="  ✗ IOMMU groups: Not found\n"
        verification_failed=true
    fi
    verification_report+="\n"

    verification_report+="═══════════════════════════════════════════════════════\n"
    if $verification_failed; then
        verification_report+="  OVERALL STATUS: ✗ VERIFICATION FAILED\n"
        verification_report+="  Some components are not correctly configured.\n"
        verification_report+="  A reboot is required for kernel parameter changes.\n"
    else
        verification_report+="  OVERALL STATUS: ✓ VERIFICATION PASSED\n"
        verification_report+="  All components correctly configured.\n"
    fi
    verification_report+="═══════════════════════════════════════════════════════\n"

    echo -e "$verification_report" | tee -a "$LOG_FILE"

    whiptail --title "Configuration Verification" --scrolltext --msgbox \
        "$verification_report" 30 70

    $verification_failed && return 1 || return 0
}

# ---------------------------------------------------------
# ISO Management Functions (Proxmox-native: search, download, attach)
# ---------------------------------------------------------

# HTTP GET helper: use curl or wget
http_get() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$url" 2>/dev/null
    else
        log_error "No HTTP client available (curl or wget required)"
        return 1
    fi
}

# Check if pvesm supports download-url (Proxmox 8+)
pvesm_supports_download_url() {
    pvesm help 2>/dev/null | grep -q "download-url"
}

# Read /etc/pve/storage.cfg and get path for dir/nfs/cifs storages
get_storage_path_from_cfg() {
    local storage="$1"
    [[ -r /etc/pve/storage.cfg ]] || return 1

    awk -v st="$storage" '
        BEGIN{inblk=0}
        /^[a-z]+:[[:space:]]+/{
            inblk=0
            type=$1; sub(":", "", type)
            name=$2
            if(name==st){inblk=1}
        }
        inblk==1 && $1=="path" {print $2; exit}
    ' /etc/pve/storage.cfg
}

# Get ISO directory for a storage
get_iso_dir_for_storage() {
    local storage="$1"
    local base
    base="$(get_storage_path_from_cfg "$storage")" || return 1
    [[ -n "$base" ]] || return 1
    echo "$base/template/iso"
}

# Download file with curl or wget
download_file() {
    local url="$1"
    local out="$2"

    if command -v curl >/dev/null 2>&1; then
        # -L follows redirects, --fail fails on 4xx/5xx
        curl -fL --retry 3 --retry-delay 2 -o "$out" "$url"
    else
        wget -O "$out" "$url"
    fi
}

# Heuristic to detect Microsoft URL expiration (403/AccessDenied)
http_status_hint() {
    grep -qiE "403|Forbidden|AccessDenied|Signature|expired|Authentication|denied" "$LOG_FILE" && return 0
    return 1
}

# List all storages that support ISO content
list_iso_storages() {
    pvesm status 2>/dev/null | awk 'NR>1 && /active/ {print $1}' | while read -r storage; do
        # Check if storage supports iso content
        if pvesm list "$storage" --content iso >/dev/null 2>&1; then
            echo "$storage"
        fi
    done
}

# Pick an ISO storage with whiptail menu
pick_iso_storage() {
    local default_preference="${1:-local}"
    local storages
    storages=$(list_iso_storages)

    if [[ -z "$storages" ]]; then
        log_error "No ISO-capable storage found"
        whiptail --title "Storage Error" --msgbox \
            "No storage found that supports ISO content.\n\nPlease configure ISO storage in Proxmox:\nDatacenter > Storage > Add > Directory/NFS" 12 70
        return 1
    fi

    local menu_items=()
    local default_storage=""
    while IFS= read -r st; do
        local type avail
        type=$(pvesm status | awk -v s="$st" '$1==s {print $2}')
        # Column 6 is Available in KB, convert to GB
        avail=$(pvesm status | awk -v s="$st" '$1==s {print int($6/1024/1024)}')  # KB -> GB
        menu_items+=("$st" "Type: $type | Available: ${avail}GB")
        if [[ "$st" == "$default_preference" ]]; then
            default_storage="$st"
        fi
    done <<< "$storages"

    # If default not found, use first
    [[ -z "$default_storage" ]] && default_storage="${menu_items[0]}"

    local choice
    choice=$(whiptail --title "Select ISO Storage" --menu \
        "Choose storage for ISO download:" 15 70 5 \
        "${menu_items[@]}" --default-item "$default_storage" 3>&1 1>&2 2>&3)

    if [[ -n "$choice" ]]; then
        echo "$choice"
        return 0
    else
        return 1
    fi
}

# List all ISOs across all storages
list_all_isos() {
    local storages
    storages=$(list_iso_storages)
    [[ -z "$storages" ]] && return 1

    while IFS= read -r st; do
        # pvesm list already returns full volid (storage:content/filename)
        pvesm list "$st" --content iso 2>/dev/null | awk 'NR>1 {print $1}'
    done <<< "$storages"
}

# Pick an existing ISO from all storages
pick_existing_iso() {
    local isos
    isos=$(list_all_isos)

    if [[ -z "$isos" ]]; then
        whiptail --title "No ISOs Found" --msgbox \
            "No ISO images found in any storage.\n\nYou can download an ISO or upload one via Proxmox UI:\nStorage > ISO Images > Upload" 10 70
        return 1
    fi

    local menu_items=()
    local count=0
    while IFS= read -r volid; do
        count=$((count + 1))
        local filename="${volid##*/}"  # Extract filename
        local storage="${volid%%:*}"   # Extract storage
        menu_items+=("$volid" "[$storage] $filename")
    done <<< "$isos"

    local choice
    choice=$(whiptail --title "Select Existing ISO" --menu \
        "Found $count ISO(s):" 20 90 12 \
        "${menu_items[@]}" 3>&1 1>&2 2>&3)

    if [[ -n "$choice" ]]; then
        echo "$choice"
        return 0
    else
        return 1
    fi
}

# Find ISO by filename across all storages
find_iso_by_filename() {
    local filename="$1"
    local isos
    isos=$(list_all_isos)

    while IFS= read -r volid; do
        if [[ "$volid" == *":iso/$filename" ]]; then
            echo "$volid"
            return 0
        fi
    done <<< "$isos"

    return 1
}

# Download ISO using pvesm (with fallback to curl/wget for older Proxmox)
pvesm_download_iso() {
    local storage="$1"
    local filename="$2"
    local url="$3"

    ISO_LAST_VOLID=""

    log_info "Downloading ISO: $filename to storage $storage"
    log_info "URL: $url"

    # If ISO already exists, skip download
    if verify_iso_exists "$storage" "$filename"; then
        ISO_LAST_VOLID="$storage:iso/$filename"
        log_success "ISO already exists: $ISO_LAST_VOLID"
        return 0
    fi

    # Method 1: Native Proxmox downloader (if supported)
    if pvesm_supports_download_url; then
        log_info "Using Proxmox-native downloader: pvesm download-url"

        (
            echo "10"; echo "XXX"; echo "20"; echo "Downloading via pvesm...\nThis may take several minutes."; echo "XXX"
            if pvesm download-url "$storage" "$url" --content iso --filename "$filename" >>"$LOG_FILE" 2>&1; then
                echo "XXX"; echo "90"; echo "Download complete, verifying..."; echo "XXX"
                echo "100"
            else
                echo "XXX"; echo "100"; echo "Download failed (pvesm)."; echo "XXX"
            fi
        ) | whiptail --gauge "Downloading ISO..." 8 70 0

        if verify_iso_exists "$storage" "$filename"; then
            ISO_LAST_VOLID="$storage:iso/$filename"
            log_success "ISO downloaded successfully: $ISO_LAST_VOLID"
            return 0
        fi

        log_error "pvesm download-url failed; ISO not found after download"
        return 1
    fi

    # Method 2: Fallback for older Proxmox (direct download with curl/wget)
    log_warning "Your Proxmox version does NOT support 'pvesm download-url'. Using fallback downloader (curl/wget)."

    local iso_dir
    iso_dir="$(get_iso_dir_for_storage "$storage")" || {
        log_error "Cannot resolve ISO directory for storage '$storage'."
        whiptail --title "ISO Download Not Supported" --msgbox \
            "This Proxmox lacks 'pvesm download-url' and PECU cannot find a filesystem path for storage '$storage'.\n\nUse a Directory/NFS/CIFS storage for ISOs (e.g. 'local'), or upload ISO via Proxmox UI." 14 75
        return 1
    }

    mkdir -p "$iso_dir" || {
        log_error "Cannot create ISO dir: $iso_dir"
        return 1
    }

    local tmp="$iso_dir/.${filename}.part"
    local dest="$iso_dir/$filename"

    log_info "Fallback download path: $dest"

    (
        echo "10"; echo "XXX"; echo "20"; echo "Downloading with curl/wget...\n$filename"; echo "XXX"
        if download_file "$url" "$tmp" >>"$LOG_FILE" 2>&1; then
            mv -f "$tmp" "$dest"
            echo "XXX"; echo "90"; echo "Download complete, verifying..."; echo "XXX"
            echo "100"
        else
            echo "XXX"; echo "100"; echo "Download failed (curl/wget)."; echo "XXX"
        fi
    ) | whiptail --gauge "Downloading ISO..." 8 70 0

    # Verification
    if [[ -s "$dest" ]]; then
        ISO_LAST_VOLID="$storage:iso/$filename"
        log_success "ISO downloaded successfully: $ISO_LAST_VOLID"
        return 0
    fi

    rm -f "$tmp" 2>/dev/null || true
    log_error "ISO download failed or file is empty: $dest"

    if http_status_hint; then
        whiptail --title "Download Failed" --msgbox \
            "Download failed.\n\nLikely cause: Microsoft download URL expired (403/AccessDenied).\nGenerate a fresh ISO link and try again.\n\nCheck log:\n$LOG_FILE" 14 70
    else
        whiptail --title "Download Failed" --msgbox \
            "Download failed.\n\nCheck:\n$LOG_FILE\n\nTip: verify internet/DNS and storage free space." 12 70
    fi

    return 1
}

# Verify ISO exists in storage
verify_iso_exists() {
    local storage="$1"
    local filename="$2"

    pvesm list "$storage" --content iso 2>/dev/null | grep -Fq "iso/$filename"
}

# Get LVM thin pool info for storage (vg/thinpool)
get_lvmthin_info_for_storage() {
    local storage="$1"
    [[ -r /etc/pve/storage.cfg ]] || return 1

    local vg tp
    vg=$(awk -v st="$storage" '
        /^[a-z]+:[[:space:]]+/{inblk=0; type=$1; sub(":", "", type); name=$2; if(name==st && type=="lvmthin"){inblk=1}}
        inblk==1 && $1=="vgname" {print $2; exit}
    ' /etc/pve/storage.cfg)

    tp=$(awk -v st="$storage" '
        /^[a-z]+:[[:space:]]+/{inblk=0; type=$1; sub(":", "", type); name=$2; if(name==st && type=="lvmthin"){inblk=1}}
        inblk==1 && $1=="thinpool" {print $2; exit}
    ' /etc/pve/storage.cfg)

    [[ -n "$vg" && -n "$tp" ]] || return 1
    echo "$vg/$tp"
}

# Estimate free space in LVM thin pool (GB)
get_lvmthin_free_gb_estimate() {
    local storage="$1"
    local vgtp
    vgtp="$(get_lvmthin_info_for_storage "$storage")" || return 1

    # lv_size in GB, data_percent in %
    local line
    line=$(lvs --noheadings --units g --nosuffix -o lv_size,data_percent "$vgtp" 2>/dev/null | tr -s ' ')
    [[ -n "$line" ]] || return 1

    local sz dp
    sz=$(echo "$line" | awk '{print $1}')
    dp=$(echo "$line" | awk '{print $2}')
    [[ -n "$sz" && -n "$dp" ]] || return 1

    awk -v size="$sz" -v used="$dp" 'BEGIN{free=size*(100-used)/100; printf "%.0f\\n", free}'
}

# Warning: prevent disk size larger than thin pool available space
warn_disk_size_vs_storage() {
    local storage="$1"
    local requested_gb="$2"

    # Only applies to lvmthin
    local free_gb
    free_gb="$(get_lvmthin_free_gb_estimate "$storage" 2>/dev/null || echo "")"
    [[ -n "$free_gb" ]] || return 0

    if [[ "$requested_gb" -gt "$free_gb" ]]; then
        whiptail --title "Storage Warning (Thin Pool)" --yesno \
"Requested disk: ${requested_gb}GB
Estimated thin-pool free: ${free_gb}GB

This can fill the pool and BREAK the host/VMs.

Reduce disk size or choose another storage.

Continue anyway? (NOT recommended)" 16 70 || return 1
    fi
    return 0
}

# Attach ISO to VM
# Parameters: vmid, volid, device, set_boot (true|false)
attach_iso_to_vm() {
    local vmid="$1"
    local volid="$2"
    local device="${3:-ide2}"
    local set_boot="${4:-false}"

    log_info "Attaching ISO $volid to VM $vmid on $device"

    if qm set "$vmid" --"$device" "$volid,media=cdrom" >> "$LOG_FILE" 2>&1; then
        # Set boot order only for installer ISOs (boot from CD first)
        if [[ "$set_boot" == "true" ]]; then
            qm set "$vmid" --boot "order=$device;scsi0" >> "$LOG_FILE" 2>&1 || true
            log_success "ISO attached to $device (boot device)"
        else
            log_success "ISO attached to $device (secondary)"
        fi
        return 0
    else
        log_error "Failed to attach ISO to VM $vmid"
        return 1
    fi
}

# Find first free IDE slot for a VM
find_free_ide_slot() {
    local vmid="$1"
    local config
    config=$(qm config "$vmid" 2>/dev/null)

    for slot in ide2 ide3 ide1 ide0; do
        if ! echo "$config" | grep -q "^$slot:"; then
            echo "$slot"
            return 0
        fi
    done

    log_error "No free IDE slots available for VM $vmid"
    return 1
}

# Resolve Debian current netinst ISO
resolve_debian_amd64_netinst_current() {
    local sha_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS"
    local base_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd"

    log_info "Resolving current Debian netinst ISO"

    local sha_content
    sha_content=$(http_get "$sha_url")
    if [[ -z "$sha_content" ]]; then
        log_error "Failed to fetch Debian SHA256SUMS"
        return 1
    fi

    # Extract latest debian-*-amd64-netinst.iso
    local filename
    filename=$(echo "$sha_content" | grep -oP 'debian-[0-9.]+-amd64-netinst\.iso' | head -n1)

    if [[ -z "$filename" ]]; then
        log_error "Failed to parse Debian netinst filename"
        return 1
    fi

    echo "$base_url/$filename|$filename"
}

# Resolve Ubuntu 24.04 server ISO
resolve_ubuntu_2404_server_amd64_latest() {
    local sha_url="https://releases.ubuntu.com/24.04/SHA256SUMS"
    local base_url="https://releases.ubuntu.com/24.04"

    log_info "Resolving Ubuntu 24.04 server ISO"

    local sha_content
    sha_content=$(http_get "$sha_url")
    if [[ -z "$sha_content" ]]; then
        log_error "Failed to fetch Ubuntu SHA256SUMS"
        return 1
    fi

    # Extract ubuntu-24.04(.X)?-live-server-amd64.iso (prefer highest point release)
    local filename
    filename=$(echo "$sha_content" | grep -oP 'ubuntu-24\.04(\.\d+)?-live-server-amd64\.iso' | sort -V | tail -n1)

    if [[ -z "$filename" ]]; then
        log_error "Failed to parse Ubuntu 24.04 filename"
        return 1
    fi

    echo "$base_url/$filename|$filename"
}

# Resolve virtio-win ISO
resolve_virtio_win_iso() {
    echo "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso|virtio-win.iso"
}

# ISO wizard: select or download ISO
iso_wizard() {
    local context="${1:-any}"  # linux|windows|any

    while true; do
        local menu_items=()
        menu_items=("1" "Use existing ISO from storage")

        # Context-aware menu with unique tags
        if [[ "$context" == "linux" ]]; then
            menu_items+=("2" "Download official Linux ISO (Debian/Ubuntu)")
            menu_items+=("3" "Download from custom URL")
            menu_items+=("4" "Cancel")
        elif [[ "$context" == "windows" ]]; then
            menu_items+=("2" "Download from custom URL")
            menu_items+=("3" "Cancel")
        else
            # context == "any"
            menu_items+=("2" "Download official Linux ISO (Debian/Ubuntu)")
            menu_items+=("3" "Download VirtIO drivers ISO (virtio-win)")
            menu_items+=("4" "Download from custom URL")
            menu_items+=("5" "Cancel")
        fi

        local choice
        choice=$(whiptail --title "ISO Selection" --menu \
            "Choose ISO source for VM template:" 16 75 7 \
            "${menu_items[@]}" 3>&1 1>&2 2>&3)

        case "$choice" in
            1)  # Existing ISO
                local volid
                volid=$(pick_existing_iso)
                if [[ -n "$volid" ]]; then
                    echo "$volid"
                    return 0
                fi
                ;;
            2)  # Context-dependent option
                if [[ "$context" == "linux" ]]; then
                    # Official Linux download
                    local distro_choice
                    distro_choice=$(whiptail --title "Select Distribution" --menu \
                        "Choose Linux distribution:" 12 70 4 \
                        "1" "Debian (current stable netinst)" \
                        "2" "Ubuntu 24.04 LTS Server" \
                        "3" "Back" 3>&1 1>&2 2>&3)

                    local url_filename
                    case "$distro_choice" in
                        1) url_filename=$(resolve_debian_amd64_netinst_current) ;;
                        2) url_filename=$(resolve_ubuntu_2404_server_amd64_latest) ;;
                        *) continue ;;
                    esac

                    if [[ -z "$url_filename" ]]; then
                        whiptail --title "Error" --msgbox "Failed to resolve ISO URL.\nCheck network connection." 8 60
                        continue
                    fi

                    local url="${url_filename%|*}"
                    local filename="${url_filename#*|}"

                    # Check if already exists
                    local existing_volid
                    existing_volid=$(find_iso_by_filename "$filename")
                    if [[ -n "$existing_volid" ]]; then
                        if whiptail --title "ISO Exists" --yesno \
                            "ISO already exists: $existing_volid\n\nReuse this ISO?" 10 70; then
                            echo "$existing_volid"
                            return 0
                        else
                            continue
                        fi
                    fi

                    # Download
                    local storage
                    storage=$(pick_iso_storage "local")
                    [[ -z "$storage" ]] && continue

                    if pvesm_download_iso "$storage" "$filename" "$url"; then
                        echo "$ISO_LAST_VOLID"
                        return 0
                    else
                        whiptail --title "Download Failed" --msgbox \
                            "Failed to download ISO.\nCheck $LOG_FILE for details." 8 60
                        continue
                    fi

                elif [[ "$context" == "windows" ]]; then
                    # Custom URL for Windows installer (option 2 in windows context)
                    local custom_url
                    custom_url=$(whiptail --inputbox "Enter Windows ISO download URL:" 10 70 "https://" 3>&1 1>&2 2>&3)
                    [[ -z "$custom_url" ]] && continue

                    local filename
                    filename=$(basename "$custom_url" | sed 's/[?#].*//')

                    if [[ ! "$filename" =~ \.iso$ ]]; then
                        filename="windows.iso"
                    fi

                    filename=$(whiptail --inputbox "ISO filename:" 10 70 "$filename" 3>&1 1>&2 2>&3)
                    [[ -z "$filename" ]] && continue

                    local existing_volid
                    existing_volid=$(find_iso_by_filename "$filename")
                    if [[ -n "$existing_volid" ]]; then
                        if whiptail --title "ISO Exists" --yesno \
                            "ISO already exists: $existing_volid\n\nReuse this ISO?" 10 70; then
                            echo "$existing_volid"
                            return 0
                        fi
                    fi

                    local storage
                    storage=$(pick_iso_storage "local")
                    [[ -z "$storage" ]] && continue

                    if pvesm_download_iso "$storage" "$filename" "$custom_url"; then
                        echo "$ISO_LAST_VOLID"
                        return 0
                    else
                        whiptail --title "Download Failed" --msgbox \
                            "Failed to download ISO.\nCheck $LOG_FILE for details." 8 60
                        continue
                    fi

                elif [[ "$context" == "any" ]]; then
                    # Official Linux download (option 2 in any context)
                    local distro_choice
                    distro_choice=$(whiptail --title "Select Distribution" --menu \
                        "Choose Linux distribution:" 12 70 4 \
                        "1" "Debian (current stable netinst)" \
                        "2" "Ubuntu 24.04 LTS Server" \
                        "3" "Back" 3>&1 1>&2 2>&3)

                    local url_filename
                    case "$distro_choice" in
                        1) url_filename=$(resolve_debian_amd64_netinst_current) ;;
                        2) url_filename=$(resolve_ubuntu_2404_server_amd64_latest) ;;
                        *) continue ;;
                    esac

                    if [[ -z "$url_filename" ]]; then
                        whiptail --title "Error" --msgbox "Failed to resolve ISO URL.\nCheck network connection." 8 60
                        continue
                    fi

                    local url="${url_filename%|*}"
                    local filename="${url_filename#*|}"

                    local existing_volid
                    existing_volid=$(find_iso_by_filename "$filename")
                    if [[ -n "$existing_volid" ]]; then
                        if whiptail --title "ISO Exists" --yesno \
                            "ISO already exists: $existing_volid\n\nReuse this ISO?" 10 70; then
                            echo "$existing_volid"
                            return 0
                        else
                            continue
                        fi
                    fi

                    local storage
                    storage=$(pick_iso_storage "local")
                    [[ -z "$storage" ]] && continue

                    if pvesm_download_iso "$storage" "$filename" "$url"; then
                        echo "$ISO_LAST_VOLID"
                        return 0
                    else
                        whiptail --title "Download Failed" --msgbox \
                            "Failed to download ISO.\nCheck $LOG_FILE for details." 8 60
                        continue
                    fi
                fi
                ;;
            3)  # Context-dependent: Custom URL (linux) or Cancel (windows) or VirtIO (any)
                if [[ "$context" == "linux" ]]; then
                    # Custom URL for linux context
                    local custom_url
                    custom_url=$(whiptail --inputbox "Enter ISO download URL:" 10 70 "https://" 3>&1 1>&2 2>&3)
                    [[ -z "$custom_url" ]] && continue

                    local filename
                    filename=$(basename "$custom_url" | sed 's/[?#].*//')

                    if [[ ! "$filename" =~ \.iso$ ]]; then
                        filename="custom.iso"
                    fi

                    filename=$(whiptail --inputbox "ISO filename:" 10 70 "$filename" 3>&1 1>&2 2>&3)
                    [[ -z "$filename" ]] && continue

                    local existing_volid
                    existing_volid=$(find_iso_by_filename "$filename")
                    if [[ -n "$existing_volid" ]]; then
                        if whiptail --title "ISO Exists" --yesno \
                            "ISO already exists: $existing_volid\n\nReuse this ISO?" 10 70; then
                            echo "$existing_volid"
                            return 0
                        fi
                    fi

                    local storage
                    storage=$(pick_iso_storage "local")
                    [[ -z "$storage" ]] && continue

                    if pvesm_download_iso "$storage" "$filename" "$custom_url"; then
                        echo "$ISO_LAST_VOLID"
                        return 0
                    else
                        whiptail --title "Download Failed" --msgbox \
                            "Failed to download ISO.\nCheck $LOG_FILE for details." 8 60
                        continue
                    fi
                elif [[ "$context" == "windows" ]]; then
                    # Cancel for windows context (option 3)
                    return 1
                elif [[ "$context" == "any" ]]; then
                    # VirtIO download for any context (option 3)
                    local url_filename
                    url_filename=$(resolve_virtio_win_iso)
                    local url="${url_filename%|*}"
                    local filename="${url_filename#*|}"

                    local existing_volid
                    existing_volid=$(find_iso_by_filename "$filename")
                    if [[ -n "$existing_volid" ]]; then
                        if whiptail --title "VirtIO ISO Exists" --yesno \
                            "VirtIO drivers ISO already exists: $existing_volid\n\nReuse this ISO?" 10 70; then
                            echo "$existing_volid"
                            return 0
                        fi
                    fi

                    local storage
                    storage=$(pick_iso_storage "local")
                    [[ -z "$storage" ]] && continue

                    if pvesm_download_iso "$storage" "$filename" "$url"; then
                        echo "$ISO_LAST_VOLID"
                        return 0
                    else
                        whiptail --title "Download Failed" --msgbox \
                            "Failed to download VirtIO ISO.\nCheck $LOG_FILE for details." 8 60
                        continue
                    fi
                fi
                ;;
            4)  # Cancel (linux) or Custom URL (any)
                if [[ "$context" == "linux" ]]; then
                    # Cancel
                    return 1
                elif [[ "$context" == "any" ]]; then
                    # Custom URL for any context
                    local custom_url
                    custom_url=$(whiptail --inputbox "Enter ISO download URL:" 10 70 "https://" 3>&1 1>&2 2>&3)
                    [[ -z "$custom_url" ]] && continue

                    local filename
                    filename=$(basename "$custom_url" | sed 's/[?#].*//')

                    if [[ ! "$filename" =~ \.iso$ ]]; then
                        filename="custom.iso"
                    fi

                    filename=$(whiptail --inputbox "ISO filename:" 10 70 "$filename" 3>&1 1>&2 2>&3)
                    [[ -z "$filename" ]] && continue

                    local existing_volid
                    existing_volid=$(find_iso_by_filename "$filename")
                    if [[ -n "$existing_volid" ]]; then
                        if whiptail --title "ISO Exists" --yesno \
                            "ISO already exists: $existing_volid\n\nReuse this ISO?" 10 70; then
                            echo "$existing_volid"
                            return 0
                        fi
                    fi

                    local storage
                    storage=$(pick_iso_storage "local")
                    [[ -z "$storage" ]] && continue

                    if pvesm_download_iso "$storage" "$filename" "$custom_url"; then
                        echo "$ISO_LAST_VOLID"
                        return 0
                    else
                        whiptail --title "Download Failed" --msgbox \
                            "Failed to download ISO.\nCheck $LOG_FILE for details." 8 60
                        continue
                    fi
                fi
                ;;
            5)  # Cancel (only for any context)
                return 1
                ;;
            *)
                return 1
                ;;
        esac
    done
}

# Maybe attach installer ISO to VM
maybe_attach_installer_iso() {
    local vmid="$1"
    local context="${2:-any}"

    if whiptail --title "Attach Installer ISO" --yesno \
        "Do you want to attach an OS installer ISO to this template?\n\nThis allows you to boot and install the OS immediately after cloning." 12 70; then

        local volid
        volid=$(iso_wizard "$context")

        if [[ -z "$volid" ]]; then
            if whiptail --title "No ISO Selected" --yesno \
                "No ISO was selected.\n\nContinue without installer ISO?" 10 60; then
                log_warning "Template created without installer ISO"
                return 0
            else
                log_error "Template creation aborted by user"
                return 1
            fi
        fi

        local device
        device=$(find_free_ide_slot "$vmid")
        if [[ -z "$device" ]]; then
            whiptail --title "Error" --msgbox "No free IDE slots available." 8 50
            return 1
        fi

        # Attach installer ISO with boot priority (set_boot=true)
        if attach_iso_to_vm "$vmid" "$volid" "$device" "true"; then
            whiptail --title "ISO Attached" --msgbox \
                "Installer ISO attached successfully:\n\nVolID: $volid\nDevice: $device\nBoot: Enabled (CD first)" 11 70
            return 0
        else
            if whiptail --title "Attach Failed" --yesno \
                "Failed to attach ISO to VM.\n\nContinue anyway?" 10 60; then
                return 0
            else
                return 1
            fi
        fi
    else
        log_info "User skipped installer ISO attachment"
        return 0
    fi
}

# Maybe attach VirtIO drivers ISO for Windows
maybe_attach_virtio_iso_windows() {
    local vmid="$1"

    if whiptail --title "VirtIO Drivers" --yesno \
        "Do you want to attach the VirtIO drivers ISO?\n\nRequired for Windows to detect virtio-scsi disk during installation.\nRecommended: Yes" 12 70; then

        local filename="virtio-win.iso"
        local volid
        volid=$(find_iso_by_filename "$filename")

        if [[ -z "$volid" ]]; then
            # Need to download
            local url_filename
            url_filename=$(resolve_virtio_win_iso)
            local url="${url_filename%|*}"

            local storage
            storage=$(pick_iso_storage "local")
            if [[ -z "$storage" ]]; then
                log_warning "VirtIO ISO download cancelled"
                return 0
            fi

            if pvesm_download_iso "$storage" "$filename" "$url"; then
                volid="$ISO_LAST_VOLID"
            else
                whiptail --title "Download Failed" --msgbox \
                    "Failed to download VirtIO ISO.\nYou can add it later manually." 8 60
                return 0
            fi
        fi

        local device
        device=$(find_free_ide_slot "$vmid")
        if [[ -z "$device" ]]; then
            whiptail --title "Warning" --msgbox \
                "No free IDE slots. VirtIO ISO not attached.\nAdd manually if needed." 8 60
            return 0
        fi

        # Attach VirtIO ISO without changing boot order (set_boot=false)
        if attach_iso_to_vm "$vmid" "$volid" "$device" "false"; then
            whiptail --title "VirtIO ISO Attached" --msgbox \
                "VirtIO drivers ISO attached to $device.\n\nDuring Windows install, use 'Load driver' and browse the ISO." 10 70
            return 0
        else
            log_warning "Failed to attach VirtIO ISO"
            return 0
        fi
    else
        log_info "User skipped VirtIO drivers ISO"
        return 0
    fi
}

# ---------------------------------------------------------
# VM Template Creation Functions (unchanged from 3.1)
# ---------------------------------------------------------

create_vm_templates() {
    local choice
    choice=$(whiptail --title "VM Template Creation" --menu \
        "Select template type to create:" 15 80 4 \
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

    if qm list | grep -q "^\\s*$vmid\\s"; then
        log_error "VM with ID $vmid already exists"
        whiptail --title "Error" --msgbox "VM ID $vmid already exists. Please choose a different ID." 8 60
        return 1
    fi

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

    # Enforce chipset/machine type (Issue #28: default moved to Q35)
    if qm set "$vmid" --machine "$DEFAULT_MACHINE_WIN_GAMING" >> "$LOG_FILE" 2>&1; then
        log_success "Set VM $vmid machine type to $DEFAULT_MACHINE_WIN_GAMING"
    else
        log_warning "Could not set machine type to $DEFAULT_MACHINE_WIN_GAMING (set manually: qm set $vmid --machine q35)"
    fi

    # Attach installer ISO if requested
    maybe_attach_installer_iso "$vmid" "windows" || return 1

    # Attach VirtIO drivers ISO if requested
    maybe_attach_virtio_iso_windows "$vmid"

    qm template "$vmid"

    log_success "Windows Gaming template created with ID $vmid"
    whiptail --title "Template Created" --msgbox \
        "Windows Gaming template created successfully!\n\nVM ID: $vmid\nName: $name\n\nTo use:\n1. Clone this template\n2. Add GPU via Hardware > Add > PCI Device\n3. Boot from ISO and install Windows\n4. Install GPU drivers" 16 70
}

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

    if qm list | grep -q "^\\s*$vmid\\s"; then
        log_error "VM with ID $vmid already exists"
        whiptail --title "Error" --msgbox "VM ID $vmid already exists. Please choose a different ID." 8 60
        return 1
    fi

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

    # Enforce chipset/machine type (Issue #28: default moved to Q35)
    if qm set "$vmid" --machine "$DEFAULT_MACHINE_LINUX_WORKSTATION" >> "$LOG_FILE" 2>&1; then
        log_success "Set VM $vmid machine type to $DEFAULT_MACHINE_LINUX_WORKSTATION"
    else
        log_warning "Could not set machine type to $DEFAULT_MACHINE_LINUX_WORKSTATION"
    fi

    # Attach installer ISO if requested
    maybe_attach_installer_iso "$vmid" "linux" || return 1

    qm template "$vmid"

    log_success "Linux Workstation template created with ID $vmid"
    whiptail --title "Template Created" --msgbox \
        "Linux Workstation template created successfully!\n\nVM ID: $vmid\nName: $name\n\nOptimized for:\n- AI/ML workloads\n- Scientific computing\n- Development work\n\nNext: Clone and boot from attached ISO" 16 70
}

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

    if qm list | grep -q "^\\s*$vmid\\s"; then
        log_error "VM with ID $vmid already exists"
        whiptail --title "Error" --msgbox "VM ID $vmid already exists. Please choose a different ID." 8 60
        return 1
    fi

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

    # Enforce chipset/machine type (Issue #28: default moved to Q35)
    if qm set "$vmid" --machine "$DEFAULT_MACHINE_MEDIA_SERVER" >> "$LOG_FILE" 2>&1; then
        log_success "Set VM $vmid machine type to $DEFAULT_MACHINE_MEDIA_SERVER"
    else
        log_warning "Could not set machine type to $DEFAULT_MACHINE_MEDIA_SERVER"
    fi

    # Attach installer ISO if requested
    maybe_attach_installer_iso "$vmid" "linux" || return 1

    qm template "$vmid"

    log_success "Media Server template created with ID $vmid"
    whiptail --title "Template Created" --msgbox \
        "Media Server template created successfully!\n\nVM ID: $vmid\nName: $name\n\nOptimized for:\n- Plex/Jellyfin transcoding\n- Hardware acceleration\n- Low resource usage\n\nNext: Clone and boot from attached ISO" 16 70
}

create_custom_template() {
    whiptail --title "Custom Template" --msgbox \
        "Custom template creation allows you to specify all parameters manually.\n\nThis is for advanced users who want full control over VM configuration." 10 70

    local vmid name memory cores storage ostype cpu_type

    while true; do
        vmid=$(whiptail --inputbox "Enter VM ID (100-999):" 8 40 "300" 3>&1 1>&2 2>&3)
        [[ -z "$vmid" ]] && return 1

        if [[ "$vmid" -lt 100 || "$vmid" -gt 999 ]]; then
            whiptail --title "Invalid Input" --msgbox "VM ID must be between 100-999." 8 60
            continue
        fi

        if qm list | grep -q "^\\s*$vmid\\s"; then
            whiptail --title "ID Exists" --msgbox "VM ID $vmid already exists. Choose a different ID." 8 60
            continue
        fi
        break
    done

    name=$(whiptail --inputbox "Enter VM name:" 8 50 "Custom-Template" 3>&1 1>&2 2>&3)
    [[ -z "$name" ]] && return 1

    while true; do
        memory=$(whiptail --inputbox "RAM in MB (min 512):" 8 50 "4096" 3>&1 1>&2 2>&3)
        [[ -z "$memory" ]] && return 1
        if [[ "$memory" -lt 512 ]]; then
            whiptail --title "Invalid Input" --msgbox "Memory must be at least 512 MB." 8 60
            continue
        fi
        break
    done

    local max_cores
    max_cores=$(nproc)
    while true; do
        cores=$(whiptail --inputbox "CPU cores (max $max_cores):" 8 50 "2" 3>&1 1>&2 2>&3)
        [[ -z "$cores" ]] && return 1
        if [[ "$cores" -lt 1 || "$cores" -gt "$max_cores" ]]; then
            whiptail --title "Invalid Input" --msgbox "CPU cores must be between 1-$max_cores." 8 60
            continue
        fi
        break
    done

    storage=$(whiptail --inputbox "Disk size (GB):" 8 50 "32" 3>&1 1>&2 2>&3)
    [[ -z "$storage" ]] && return 1

    ostype=$(whiptail --title "OS Type" --menu "Select OS type:" 15 70 4 \
        "l26" "Linux 2.6/3.x/4.x/5.x kernel" \
        "win11" "Windows 11/2022" \
        "win10" "Windows 10/2016/2019" \
        "other" "Other OS" 3>&1 1>&2 2>&3)
    [[ -z "$ostype" ]] && return 1

    cpu_type=$(whiptail --title "CPU Type" --menu "Select CPU type:" 15 70 4 \
        "host" "Host CPU (best performance)" \
        "kvm64" "KVM default (compatible)" \
        "x86-64-v2" "x86-64-v2 (modern)" \
        "x86-64-v3" "x86-64-v3 (latest)" 3>&1 1>&2 2>&3)
    [[ -z "$cpu_type" ]] && return 1

    log_info "Creating custom VM template..."

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

    # Enforce chipset/machine type (Issue #28: default moved to Q35)
    if qm set "$vmid" --machine "$DEFAULT_MACHINE_CUSTOM" >> "$LOG_FILE" 2>&1; then
        log_success "Set VM $vmid machine type to $DEFAULT_MACHINE_CUSTOM"
    else
        log_warning "Could not set machine type to $DEFAULT_MACHINE_CUSTOM"
    fi

    # Determine context based on ostype
    local iso_context="any"
    if [[ "$ostype" =~ ^win ]]; then
        iso_context="windows"
    elif [[ "$ostype" == "l26" ]]; then
        iso_context="linux"
    fi

    # Attach installer ISO if requested
    maybe_attach_installer_iso "$vmid" "$iso_context" || return 1

    # For Windows, also offer VirtIO ISO
    if [[ "$iso_context" == "windows" ]]; then
        maybe_attach_virtio_iso_windows "$vmid"
    fi

    qm template "$vmid"

    log_success "Custom template created with ID $vmid"
    whiptail --title "Template Created" --msgbox \
        "Custom template created successfully!\n\nVM ID: $vmid\nName: $name\nOS Type: $ostype\nCPU: $cpu_type\n\nTo add GPU passthrough:\n1. Clone this template\n2. Add GPU via Hardware > Add > PCI Device\n3. Boot and install OS" 17 70
}

# ---------------------------------------------------------
# Rollback and Cleanup Functions
# ---------------------------------------------------------

rollback_gpu_passthrough() {
    log_info "Starting complete GPU passthrough rollback..."

    if ! whiptail --title "Confirm Rollback" --yesno \
        "This will completely remove all GPU passthrough configuration:\n\n• Remove IOMMU kernel parameters\n• Remove VFIO configuration\n• Remove driver blacklists\n• Update initramfs\n\nContinue?" 15 75; then
        return 0
    fi

    local rollback_success=true

    log_info "Removing kernel parameters..."
    case "$BOOT_TYPE" in
        "systemd-boot")
            if [[ -f "/etc/kernel/cmdline" ]]; then
                cp "/etc/kernel/cmdline" "$BACKUP_DIR/cmdline.rollback.$(date +%Y%m%d_%H%M%S)"
                sed -i 's/ intel_iommu=on//g; s/ amd_iommu=on//g; s/ iommu=pt//g' /etc/kernel/cmdline
                sed -i 's/ video=efifb:off//g; s/ initcall_blacklist=sysfb_init//g' /etc/kernel/cmdline
                sed -i 's/ pcie_acs_override=downstream//g' /etc/kernel/cmdline
                if command -v proxmox-boot-tool >/dev/null 2>&1; then
                    proxmox-boot-tool refresh || rollback_success=false
                else
                    pve-efiboot-tool refresh || rollback_success=false
                fi
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

    log_info "Removing configuration files..."
    local configs=("$VFIO_CONFIG" "$BLACKLIST_CONFIG" "$KVM_CONFIG" "/etc/modules-load.d/vfio.conf" "$VFIO_IOMMU_CONFIG" "/etc/modules-load.d/vendor-reset.conf")
    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            mv "$config" "$BACKUP_DIR/$(basename "$config").removed.$(date +%Y%m%d_%H%M%S)" || rollback_success=false
        fi
    done

    if whiptail --title "Remove Repository Config" --yesno \
        "Also remove PECU-managed APT repository configuration?\n\nFile: /etc/apt/sources.list.d/pecu-repos.list" 10 75; then
        remove_pecu_repos "/etc/apt/sources.list.d/pecu-repos.list"
    fi

    if lsmod | grep -q "vendor_reset"; then
        log_info "Removing vendor-reset..."
        rmmod vendor_reset 2>/dev/null || true
        if dkms status | grep -q "vendor-reset"; then
            dkms remove vendor-reset --all || true
        fi
    fi

    log_info "Updating initramfs..."
    update-initramfs -u -k all || rollback_success=false

    cat > "$STATE_FILE" << EOF
# PECU Configuration State File - Reset on $(date)
INITIALIZED=true
IOMMU_CONFIGURED=false
VFIO_CONFIGURED=false
GPU_BLACKLISTED=false
PASSTHROUGH_READY=false
EOF
    chmod 600 "$STATE_FILE" 2>/dev/null || true

    if $rollback_success; then
        log_success "GPU passthrough rollback completed successfully"
        if whiptail --title "Rollback Complete" --yesno \
            "GPU passthrough configuration has been removed.\n\nA reboot is required to apply all changes.\n\nReboot now?" 10 70; then
            reboot
        fi
        return 0
    else
        log_error "Some rollback operations failed"
        whiptail --title "Rollback Issues" --msgbox \
            "Rollback completed with some errors.\nCheck the log file for details:\n$LOG_FILE" 10 70
        return 1
    fi
}

# ---------------------------------------------------------
# Utility Functions
# ---------------------------------------------------------

show_loading_banner() {
    clear

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
    echo -e "${BLUE}║${PURPLE}                          Version ${VERSION}                                     ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                                           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    sleep 1
    clear
}

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

ask_for_reboot() {
    if whiptail --title "Reboot Required" --yesno \
        "A system reboot is required to apply the changes.\n\nReboot now?" 8 60; then
        log_info "User requested reboot"
        sync
        reboot
    else
        log_info "Reboot postponed by user"
        whiptail --title "Reboot Postponed" --msgbox \
            "Changes will take effect after next reboot.\n\nDon't forget to reboot when convenient!" 9 70
    fi
}

# ---------------------------------------------------------
# Complete GPU Passthrough Configuration Workflow
# ---------------------------------------------------------

complete_gpu_passthrough_setup() {
    log_info "Starting complete GPU passthrough configuration..."

    log_info "Step 1/8: System detection and hardware validation"
    progress_indicator "Detecting system configuration..." 2

    detect_system_info
    check_hardware_requirements || return 1

    log_info "Step 2/8: GPU detection and IOMMU analysis"
    progress_indicator "Scanning for GPU devices..." 2

    detect_gpus || return 1

    if ! check_iommu_groups; then
        if ! whiptail --title "IOMMU Issues" --yesno \
            "IOMMU group issues detected.\n\nContinue anyway?\n(You may need ACS override)" 10 70; then
            return 1
        fi
    fi

    log_info "Step 3/8: Installing dependencies"
    progress_indicator "Installing required packages..." 3

    configure_sources_list
    install_dependencies || return 1

    log_info "Step 4/8: Configuring IOMMU"
    progress_indicator "Configuring IOMMU kernel parameters..." 2

    configure_iommu || return 1

    if whiptail --title "Additional Parameters" --yesno \
        "Configure additional kernel parameters?\n(Recommended for better compatibility)" 9 70; then
        configure_additional_parameters
    fi

    log_info "Step 5/8: Configuring VFIO modules"
    progress_indicator "Setting up VFIO modules..." 2

    configure_vfio_modules || return 1

    log_info "Step 6/8: Configuring GPU driver blacklist"
    progress_indicator "Configuring driver blacklist..." 2

    blacklist_gpu_drivers || return 1

    log_info "Step 7/8: Configuring VFIO device bindings"
    progress_indicator "Setting up VFIO device bindings..." 2

    configure_vfio_device_ids || return 1

    log_info "Step 8/8: Final configurations"
    progress_indicator "Applying final configurations..." 2

    configure_kvm_options

    if lspci | grep -qi "AMD" && whiptail --title "AMD GPU Reset" --yesno \
        "Install vendor-reset for AMD GPU reset bug fix?\n\n(Does not work on every AMD GPU)" 10 70; then
        install_vendor_reset
    fi

    sed -i 's/PASSTHROUGH_READY=false/PASSTHROUGH_READY=true/' "$STATE_FILE" 2>/dev/null || true

    log_success "Complete GPU passthrough configuration finished!"

    verify_configuration_live || true

    if whiptail --title "Configuration Complete" --yesno \
        "GPU Passthrough configuration completed!\n\n✅ IOMMU configured\n✅ VFIO modules set up\n✅ GPU drivers blacklisted\n✅ Device bindings configured\n✅ KVM options optimized\n\nNext steps:\n1. REBOOT the system\n2. Verify configuration after reboot\n3. Create VM templates\n4. Add GPU to VMs via Hardware menu\n\nReboot now?" 22 70; then
        ask_for_reboot
    fi

    return 0
}

# ---------------------------------------------------------
# Menu System
# ---------------------------------------------------------

hardware_detection_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Hardware Detection & Validation" --menu \
            "System hardware detection and validation options:" 20 90 10 \
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
                    "CPU Vendor: $CPU_VENDOR\nBoot Type: $BOOT_TYPE\nIOMMU Status: $IOMMU_STATUS" 10 60
                ;;
            3) detect_gpus ;;
            4) check_iommu_groups ;;
            5) check_passthrough_status ;;
            6) verify_configuration_live ;;
            7)
                local dmesg_output
                dmesg_output=$(dmesg | grep -i "iommu\|vfio\|amd-vi\|dmar" | tail -40)
                whiptail --title "System Logs" --scrolltext --msgbox "$dmesg_output" 20 95
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

configuration_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "GPU Passthrough Configuration" --menu \
            "Configure GPU passthrough components:" 22 90 13 \
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
            12 "Repair VFIO Config (Fix invalid vfio.conf)" \
            13 "Back to Main Menu" \
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
            12) repair_vfio_conf ;;
            13) break ;;
            *) break ;;
        esac
    done
}

vm_templates_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "VM Templates & Management" --menu \
            "Create and manage VM templates for GPU passthrough:" 17 80 7 \
            1 "Create Windows Gaming Template" \
            2 "Create Linux Workstation Template" \
            3 "Create Media Server Template" \
            4 "Create Custom Template" \
            5 "ISO Library (Download/Attach ISOs)" \
            6 "List Existing Templates" \
            7 "Back to Main Menu" \
            3>&1 1>&2 2>&3)

        case "$choice" in
            1) create_windows_gaming_template ;;
            2) create_linux_workstation_template ;;
            3) create_media_server_template ;;
            4) create_custom_template ;;
            5)
                # ISO Library
                local volid
                volid=$(iso_wizard "any")
                if [[ -n "$volid" ]]; then
                    if whiptail --title "ISO Ready" --yesno \
                        "ISO selected/downloaded:\n\n$volid\n\nAttach to an existing VM?" 12 70; then
                        local target_vmid
                        target_vmid=$(whiptail --inputbox "Enter VM ID to attach ISO:" 8 50 3>&1 1>&2 2>&3)
                        if [[ -n "$target_vmid" ]]; then
                            if qm list | grep -q "^\\s*$target_vmid\\s"; then
                                local device
                                device=$(find_free_ide_slot "$target_vmid")
                                if [[ -n "$device" ]]; then
                                    # Manual attach: don't change boot order (set_boot=false)
                                    if attach_iso_to_vm "$target_vmid" "$volid" "$device" "false"; then
                                        whiptail --title "Success" --msgbox \
                                            "ISO attached to VM $target_vmid on $device" 8 60
                                    else
                                        whiptail --title "Error" --msgbox \
                                            "Failed to attach ISO. Check logs." 8 50
                                    fi
                                else
                                    whiptail --title "Error" --msgbox \
                                        "No free IDE slots on VM $target_vmid" 8 50
                                fi
                            else
                                whiptail --title "Error" --msgbox "VM $target_vmid not found." 8 50
                            fi
                        fi
                    else
                        whiptail --title "ISO Library" --msgbox \
                            "ISO is ready in storage:\n\n$volid\n\nYou can attach it manually via Proxmox UI." 10 70
                    fi
                fi
                ;;
            6)
                local templates
                templates=$(qm list | grep "template" || true)
                if [[ -n "$templates" ]]; then
                    whiptail --title "Existing Templates" --scrolltext --msgbox "$templates" 15 90
                else
                    whiptail --title "Templates" --msgbox "No templates found." 8 50
                fi
                ;;
            7) break ;;
            *) break ;;
        esac
    done
}

advanced_tools_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Advanced Tools & Troubleshooting" --menu \
            "Advanced configuration and troubleshooting tools:" 18 90 8 \
            1 "Complete Rollback (Remove All Configuration)" \
            2 "View Configuration Files" \
            3 "Manual Kernel Parameter Viewer" \
            4 "VFIO Device Bind Status" \
            5 "System Backup Info" \
            6 "View Detailed Logs" \
            7 "Repair VFIO Config (Fix invalid vfio.conf)" \
            8 "Back to Main Menu" \
            3>&1 1>&2 2>&3)

        case "$choice" in
            1) rollback_gpu_passthrough ;;
            2)
                local file_choice
                file_choice=$(whiptail --title "View Config Files" --menu "Select file to view:" 14 70 6 \
                    1 "VFIO Config (/etc/modprobe.d/vfio.conf)" \
                    2 "Blacklist Config" \
                    3 "KVM Config" \
                    4 "VFIO Modules" \
                    5 "VFIO IOMMU Config" \
                    6 "Back" \
                    3>&1 1>&2 2>&3)

                case "$file_choice" in
                    1) [[ -f "$VFIO_CONFIG" ]] && whiptail --title "VFIO Config" --textbox "$VFIO_CONFIG" 25 95 || whiptail --title "Error" --msgbox "File not found: $VFIO_CONFIG" 8 70 ;;
                    2) [[ -f "$BLACKLIST_CONFIG" ]] && whiptail --title "Blacklist Config" --textbox "$BLACKLIST_CONFIG" 25 95 || whiptail --title "Error" --msgbox "File not found: $BLACKLIST_CONFIG" 8 70 ;;
                    3) [[ -f "$KVM_CONFIG" ]] && whiptail --title "KVM Config" --textbox "$KVM_CONFIG" 25 95 || whiptail --title "Error" --msgbox "File not found: $KVM_CONFIG" 8 70 ;;
                    4) [[ -f "/etc/modules-load.d/vfio.conf" ]] && whiptail --title "VFIO Modules" --textbox "/etc/modules-load.d/vfio.conf" 25 95 || whiptail --title "Error" --msgbox "File not found: /etc/modules-load.d/vfio.conf" 8 70 ;;
                    5) [[ -f "$VFIO_IOMMU_CONFIG" ]] && whiptail --title "VFIO IOMMU Config" --textbox "$VFIO_IOMMU_CONFIG" 25 95 || whiptail --title "Error" --msgbox "File not found: $VFIO_IOMMU_CONFIG" 8 70 ;;
                esac
                ;;
            3)
                local current_params=""
                case "$BOOT_TYPE" in
                    "systemd-boot")
                        [[ -f "/etc/kernel/cmdline" ]] && current_params=$(cat /etc/kernel/cmdline)
                        ;;
                    "grub-uefi"|"grub-legacy")
                        [[ -f "/proc/cmdline" ]] && current_params=$(cat /proc/cmdline)
                        ;;
                esac

                whiptail --title "Kernel Parameters" --scrolltext --msgbox \
                    "Current kernel parameters:\n\n$current_params" 18 95
                ;;
            4)
                local bound_devices
                bound_devices=$(find /sys/bus/pci/drivers/vfio-pci -name "0000:*" 2>/dev/null | wc -l)
                local vfio_info="VFIO-bound devices: $bound_devices\n\n"

                if [[ $bound_devices -gt 0 ]]; then
                    vfio_info+="Bound devices:\n"
                    for device in $(find /sys/bus/pci/drivers/vfio-pci -name "0000:*" 2>/dev/null); do
                        local device_id
                        device_id=$(basename "$device")
                        vfio_info+="- $device_id: $(lspci -s "$device_id" | cut -d' ' -f2-)\n"
                    done
                else
                    vfio_info+="No devices currently bound to VFIO.\n"
                fi

                whiptail --title "VFIO Device Status" --scrolltext --msgbox "$vfio_info" 20 95
                ;;
            5)
                local backup_info="Backup directory: $BACKUP_DIR\nFiles backed up: $(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)"
                whiptail --title "Backup Information" --msgbox "$backup_info" 10 70
                ;;
            6)
                if [[ -f "$LOG_FILE" ]]; then
                    local tmp_log
                    tmp_log=$(mktemp)
                    tail -80 "$LOG_FILE" > "$tmp_log"
                    whiptail --title "PECU Logs (Last 80 lines)" --textbox "$tmp_log" 25 95
                    rm -f "$tmp_log"
                else
                    whiptail --title "Logs" --msgbox "No log file found." 8 60
                fi
                ;;
            7) repair_vfio_conf ;;
            8) break ;;
            *) break ;;
        esac
    done
}

help_menu() {
    while true; do
        local choice
        choice=$(whiptail --title "Help & Information" --menu \
            "Help, documentation, and support information:" 16 80 7 \
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
                    "Proxmox Enhanced Configuration Utility (PECU) v$VERSION\n\nA comprehensive tool for configuring GPU passthrough on Proxmox VE systems.\n\nAuthor: $AUTHOR\nBuild Date: $BUILD_DATE\nGitHub: github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility" 15 80
                ;;
            2)
                whiptail --title "GPU Passthrough Guide" --msgbox \
                    "GPU Passthrough Setup Process:\n\n1. Enable IOMMU in BIOS/UEFI\n2. Configure IOMMU kernel parameters\n3. Load VFIO modules\n4. Blacklist GPU host drivers\n5. Bind GPU to VFIO\n6. Create VM with Q35 chipset and UEFI\n7. Add GPU as PCI device\n8. Install guest OS and GPU drivers\n\nUse 'Complete Setup' for automated configuration." 18 80
                ;;
            3)
                whiptail --title "Troubleshooting" --msgbox \
                    "Common Issues:\n\n• No IOMMU groups: Enable VT-d/AMD-Vi in BIOS\n• GPU not isolated: May need ACS override\n• Code 43 (NVIDIA): Use hidden CPU flag\n• AMD reset bug: vendor-reset may help\n• VM won't start: Check UEFI and Q35 chipset\n• vfio.conf 'bad line' errors: Use 'Repair VFIO Config'\n\nCheck logs in $LOG_FILE for details." 18 80
                ;;
            4)
                whiptail --title "Support PECU" --msgbox \
                    "PECU is developed and maintained by:\n$AUTHOR\n\nSupport development:\n\n• BuyMeACoffee: $BMAC_URL\n• Patreon: $PATRON_URL\n• Website: $WEBSITE_URL" 15 80
                ;;
            5)
                whiptail --title "System Requirements" --msgbox \
                    "GPU Passthrough Requirements:\n\n• CPU with VT-x/AMD-V and VT-d/AMD-Vi\n• Motherboard with IOMMU support\n• GPU with UEFI GOP support (recommended)\n• Sufficient RAM for host and guest\n• Proxmox VE 7.0+ (8.x/9.x recommended)\n\nOptional:\n• Second GPU for host display\n• IPMI for remote access" 18 80
                ;;
            6)
                whiptail --title "License" --msgbox \
                    "MIT License\n\nCopyright (c) 2025-2026 Daniel Puente García\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software." 15 80
                ;;
            7) break ;;
            *) break ;;
        esac
    done
}

main_menu() {
    while true; do
        local choice
        choice=$(whiptail --backtitle "PECU v$VERSION | By Daniel Puente García (@Danilop95) | Support: $BMAC_URL | $WEBSITE_URL" \
            --title "PROXMOX ENHANCED CONFIG UTILITY" --menu \
            "Complete GPU passthrough configuration and management suite\nSupports NVIDIA, AMD, Intel GPUs | IOMMU | VFIO | VM Templates\n\nSelect an option:" \
            20 90 9 \
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
                    "Thank you for using PECU!\n\nAre you sure you want to exit?" 8 60; then
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
    check_root
    check_deps
    create_directories
    show_loading_banner
    detect_system_info
    main_menu

    clear
    echo -e "${GREEN}Thank you for using PECU v$VERSION!${NC}"
    echo -e "${CYAN}GPU Passthrough Configuration Utility${NC}"
    echo -e "${YELLOW}By $AUTHOR${NC}"
    echo ""
    echo -e "${BLUE}Support development: $BMAC_URL${NC}"
    echo ""

    log_success "PECU session ended"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

exit 0
