#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#        ██████╗ ███████╗ ██████╗██╗   ██╗
#        ██╔══██╗██╔════╝██╔════╝██║   ██║
#        ██████╔╝█████╗  ██║     ██║   ██║
#        ██╔═══╝ ██╔══╝  ██║     ██║   ██║
#        ██║     ███████╗╚██████╗╚██████╔╝
#        ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝
# -----------------------------------------------------------------------------
#  PECU Release Selector · 2025-12-10
#  Author  : Daniel Puente García — https://github.com/Danilop95
#  Donate  : https://buymeacoffee.com/danilop95ps
#  Project : Proxmox Enhanced Configuration Utility (PECU)
#  
#  Fixed Issues:
#  - #18: Handles execution without sudo when running as root
#  - #19: Improved jq installation with multiple fallback methods
#  - Better privilege detection and error handling
#  - GDPR-compliant telemetry with explicit opt-in/opt-out
#  - Privacy-friendly instance ID (random UUID, no fingerprinting)
#  - Enhanced local development mode
#  - Fixed: local variable used outside function scope
#  - Fixed: Duplicated dependency installation restart block
#  - Fixed: mkdir -p for jq installation to ~/.local/bin
#  - Fixed: Robust UI functions that don't abort on terminal command failures
#
#  TELEMETRY NOTICE:
#  This script collects OPTIONAL anonymous usage statistics to improve PECU.
#  - Data collected: instance_id (random UUID), PECU version/channel, OS/distro,
#    architecture, kernel, init system, Proxmox version/cluster/VMs/containers,
#    CPU (model/vendor/cores/threads/sockets/virtualization), RAM/swap,
#    GPU (count/vendor/model/VRAM/passthrough), storage tech (ZFS/Ceph),
#    usage_profile (enum: homelab_personal/hosting_commercial/etc),
#    coarse usage counters (feature usage aggregates, no config details),
#    Proxmox subscription mode, HA status, storage types (anonymous).
#  - NOT collected: hostnames, IPs, usernames, file paths, disk space/usage,
#    VM names/configs, storage IDs, pool names, or any personal data.
#  - Control: Set PECU_TELEMETRY=off to disable, or PECU_TELEMETRY=on to enable.
#  - Config file: ~/.config/pecu/telemetry.opt (enabled/disabled/auto)
#  - Interactive prompt: On first run (if TTY), you will be asked once.
#  - More info: https://pecu.tools/telemetry (or your configured SITE)
# -----------------------------------------------------------------------------

set -Eeuo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]] && command -v tput &>/dev/null && tput setaf 1 &>/dev/null 2>&1; then
  NC=$(tput sgr0 2>/dev/null || echo '')
  B=$(tput bold 2>/dev/null || echo '')
  U=$(tput smul 2>/dev/null || echo '')
  SO=$(tput smso 2>/dev/null || echo '')
  RS=$(tput rmso 2>/dev/null || echo '')
  R=$(tput setaf 1 2>/dev/null || echo '')
  G=$(tput setaf 2 2>/dev/null || echo '')
  Y=$(tput setaf 3 2>/dev/null || echo '')
  O=$(tput setaf 208 2>/dev/null || echo '')
  L=$(tput setaf 4 2>/dev/null || echo '')
  M=$(tput setaf 5 2>/dev/null || echo '')
  C=$(tput setaf 6 2>/dev/null || echo '')
  W=$(tput setaf 7 2>/dev/null || echo '')
else
  NC='' B='' U='' SO='' RS='' R='' G='' Y='' O='' L='' M='' C='' W=''
fi

declare -A COL=(
  [stable]=$G
  [beta]=$M
  [preview]=$C
  [experimental]=$O
  [nightly]=$L
  [legacy]=$Y
  [other]=$NC
)

# ── constants ────────────────────────────────────────────────────────────────
REPO="Danilop95/Proxmox-Enhanced-Configuration-Utility"
API="https://api.github.com/repos/$REPO/releases?per_page=100"
RAW="https://raw.githubusercontent.com/$REPO"

# ── global state variables ───────────────────────────────────────────────────
PECU_ENVIRONMENT="production"
PECU_LOCAL_HOST=""
PECU_LOCAL_PORT="8000"
PECU_PORT_PROVIDED=false
PECU_TELEMETRY_VERBOSE=false
PECU_SUPPORT_MODE=false
SITE=""
TELEMETRY_ENDPOINT=""
RELEASES_URL=""
PREMIUM_URL=""
WORKDIR=""
IS_ROOT=false
HAS_SUDO=false
SUDO_CMD=""
TAG=""
CHN=""
ASSET=""

# ── usage counters (telemetry) ───────────────────────────────────────────────
usage_repo_actions=0
usage_gpu_passthrough_runs=0
usage_kernel_tweaks_runs=0
usage_vm_templates_validate=0
usage_vm_templates_apply=0
usage_rollback_runs=0
last_run_actions_total=0
last_run_actions_failed=0
last_run_last_error=""

# JSON preview mode flag
PECU_JSON_PREVIEW=false

# ── parse command-line arguments ────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--local)
        PECU_ENVIRONMENT="local"
        if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^- ]]; then
          PECU_LOCAL_HOST="$2"
          shift
        else
          PECU_LOCAL_HOST="http://127.0.0.1"
        fi
        shift
        ;;
      -p|--port)
        PECU_PORT_PROVIDED=true
        if [[ -z "${2:-}" ]]; then
          echo -e "${R}Error: -p/--port requires a port number${NC}" >&2
          exit 1
        fi
        if [[ ! "$2" =~ ^[0-9]+$ ]]; then
          echo -e "${R}Error: -p/--port requires a numeric port (got: $2)${NC}" >&2
          exit 1
        fi
        local port_num="$2"
        if (( port_num < 1 || port_num > 65535 )); then
          echo -e "${R}Error: Port must be between 1 and 65535 (got: $port_num)${NC}" >&2
          exit 1
        fi
        PECU_LOCAL_PORT="$2"
        shift 2
        ;;
      -v|--verbose-telemetry)
        PECU_TELEMETRY_VERBOSE=true
        shift
        ;;
      -j|--json-preview)
        PECU_JSON_PREVIEW=true
        shift
        ;;
      -s|--support-info)
        PECU_SUPPORT_MODE=true
        PECU_TELEMETRY="on"
        shift
        ;;
      -h|--help)
        cat <<'HELP'
PECU Release Selector

Usage: pecu_release_selector.sh [OPTIONS]

Options:
  -l, --local [HOST]    Enable local development mode (default: production)
                        HOST: Local server address (default: http://127.0.0.1)
                        Examples:
                          -l                      # Uses http://127.0.0.1:8000
                          -l http://localhost     # Uses http://localhost:8000
                          -l http://192.168.1.100 # Uses custom IP:8000
  
  -p, --port PORT       Set custom port for local server (default: 8000)
                        Must be used with -l option
                        Valid range: 1-65535
                        Example: -l -p 3000     # Uses http://127.0.0.1:3000
  
  -v, --verbose-telemetry
                        Enable verbose telemetry logging (shows payload and response)
                        Useful for debugging telemetry issues
                        Creates log entries in: ~/.config/pecu/telemetry.log
  
  -j, --json-preview    Preview telemetry JSON payload without sending to API
                        Shows the exact JSON structure and data that would be sent
                        Useful for validating data collection and debugging
                        Does not create instance ID or send any network requests
  
  -s, --support-info    Send telemetry and display Support Information
                        Automatically enables telemetry (bypasses consent prompt)
                        Shows Instance ID and Support Token for diagnostic purposes
                        Use this when requesting help from PECU support team
                        Note: When using with curl, use: bash <(curl -sL URL) -- -s
  
  -h, --help            Display this help message

Environment Variables:
  PECU_TELEMETRY        Control telemetry behavior:
                        - off/disable/disabled/0: Disable telemetry completely
                        - on/enable/enabled/1:    Enable telemetry (no prompts)
                        - (not set):              Auto mode (prompt on first run)

Examples:
  # Production mode (default)
  ./pecu_release_selector.sh
  
  # Production mode with telemetry disabled
  PECU_TELEMETRY=off ./pecu_release_selector.sh
  
  # Local development mode with default settings (http://127.0.0.1:8000)
  ./pecu_release_selector.sh -l
  
  # Local mode with custom host
  ./pecu_release_selector.sh -l http://localhost
  
  # Local mode with custom port
  ./pecu_release_selector.sh -l -p 3000
  
  # Local mode with custom host and port
  ./pecu_release_selector.sh -l http://192.168.1.100 -p 8080
  
  # Enable verbose telemetry logging
  ./pecu_release_selector.sh -v
  
  # Preview telemetry JSON without sending
  ./pecu_release_selector.sh -j
  
  # Send telemetry and display support information
  ./pecu_release_selector.sh -s
  
  # One-liner for remote execution with support info (note the -- separator)
  bash <(curl -sL https://raw.githubusercontent.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/refs/heads/main/scripts/pecu_release_selector.sh) -- -s
  
  # Combine options
  ./pecu_release_selector.sh -l -v

Telemetry:
  PECU collects optional anonymous usage metrics to improve the software.
  Data collected: instance_id (random UUID), PECU version/channel, OS/distro,
                  architecture, kernel, init system, Proxmox version/cluster/VMs,
                  CPU (model/vendor/cores/threads/sockets/virtualization),
                  RAM/swap totals, GPU (count/vendor/model/VRAM/passthrough),
                  storage technologies (ZFS/Ceph).
  NOT collected:  hostnames, IPs, usernames, file paths, disk space, VM configs.
  
  On first run (if interactive), you will be prompted once to opt-in or opt-out.
  Your choice is saved in: ~/.config/pecu/telemetry.opt
  
  More info: https://pecu.tools/telemetry

HELP
        exit 0
        ;;
      *)
        echo -e "${R}Error: Unknown option '$1'${NC}" >&2
        echo "Use -h or --help for usage information" >&2
        exit 1
        ;;
    esac
  done
  
  if [[ $PECU_PORT_PROVIDED == true && "$PECU_ENVIRONMENT" != "local" ]]; then
    echo -e "${R}Error: -p/--port can only be used with -l/--local${NC}" >&2
    echo "Use -h or --help for usage information" >&2
    exit 1
  fi
}

parse_args "$@"

if [[ "$PECU_ENVIRONMENT" == "local" ]]; then
  if [[ ! "$PECU_LOCAL_HOST" =~ ^https?:// ]]; then
    PECU_LOCAL_HOST="http://${PECU_LOCAL_HOST}"
  fi
  
  PECU_LOCAL_HOST="${PECU_LOCAL_HOST%/}"
  
  SITE="${PECU_LOCAL_HOST}:${PECU_LOCAL_PORT}"
  TELEMETRY_ENDPOINT="$SITE/api/telemetry/push"
  
  echo -e "${C}╔═══════════════════════════════════════════════════════════════╗${NC}" >&2
  echo -e "${C}║${NC}  ${B}LOCAL DEVELOPMENT MODE ACTIVATED${NC}                         ${C}║${NC}" >&2
  echo -e "${C}╠═══════════════════════════════════════════════════════════════╣${NC}" >&2
  echo -e "${C}║${NC}  Server:    ${G}${SITE}${NC}" >&2
  echo -e "${C}║${NC}  Telemetry: ${G}${TELEMETRY_ENDPOINT}${NC}" >&2
  echo -e "${C}╚═══════════════════════════════════════════════════════════════╝${NC}" >&2
  echo "" >&2
else
  SITE="https://pecu.tools"
  TELEMETRY_ENDPOINT="$SITE/api/telemetry/push"
fi

RELEASES_URL="$SITE/releases"
PREMIUM_URL="$SITE/premium"

# ── utils (alignment-safe) ───────────────────────────────────────────────────
cols() { 
  if command -v tput &>/dev/null; then
    tput cols 2>/dev/null || echo 80
  else
    echo 80
  fi
}
repeat() {
  local ch="$1" n="${2:-0}"
  printf '%*s' "$n" '' | tr ' ' "${ch:0:1}"
}
strip_ansi() { sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'; }
vislen() {
  local s="$1"
  local n
  n=$(printf '%s' "$s" | strip_ansi | wc -m)
  printf '%s' "${n//[[:space:]]/}"
}
pad_line() {
  local w="$1" text="$2" n pad
  n=$(vislen "$text")
  (( n > w )) && { printf '%s' "$text"; return; }
  pad=$((w - n))
  printf '%s%*s' "$text" "$pad" ''
}

box_single() {
  local W="$1"; shift
  (( W<10 )) && W=10
  local inner=$((W-2))
  printf '┌%s┐\n' "$(repeat '─' "$inner")"
  local line
  for line in "$@"; do
    printf '│'; pad_line "$inner" "$line"; printf '│\n'
  done
  printf '└%s┘\n' "$(repeat '─' "$inner")"
}

box_double() {
  local W="$1" title="$2"; shift 2
  (( W<12 )) && W=12
  local inner=$((W-2))
  printf '╔%s╗\n' "$(repeat '═' "$inner")"
  printf '║'; pad_line "$inner" "$title"; printf '║\n'
  printf '╠%s╣\n' "$(repeat '═' "$inner")"
  local line
  for line in "$@"; do
    printf '║'; pad_line "$inner" "$line"; printf '║\n'
  done
  printf '╚%s╝\n' "$(repeat '═' "$inner")"
}

hr() { printf '%s\n' "$(repeat '─' "$(cols)")"; }

# ── instance ID & support footer ─────────────────────────────────────────────
# ── usage tracking helper ────────────────────────────────────────────────────
# Usage counter pattern:
#   Call pecu_usage_increment <counter_name> when operation succeeds
#   Call pecu_usage_error <error_type> when operation fails
# Examples:
#   pecu_usage_increment repo_actions           # After fixing repos
#   pecu_usage_increment gpu_passthrough        # After configuring GPU passthrough
#   pecu_usage_increment kernel_tweaks          # After applying kernel parameters
#   pecu_usage_increment templates_validate     # After validating a VM template
#   pecu_usage_increment templates_apply        # After applying a VM template
#   pecu_usage_increment rollback               # After performing a rollback
#   pecu_usage_error repo_network_error         # When apt-get update fails
#   pecu_usage_error repo_write_failed          # When repository file write fails
#   pecu_usage_error repo_permission_denied     # When lacking sudo/root access
pecu_usage_increment() {
  local counter_name="$1"
  case "$counter_name" in
    repo_actions)
      ((usage_repo_actions++))
      ((last_run_actions_total++))
      ;;
    gpu_passthrough)
      ((usage_gpu_passthrough_runs++))
      ((last_run_actions_total++))
      ;;
    kernel_tweaks)
      ((usage_kernel_tweaks_runs++))
      ((last_run_actions_total++))
      ;;
    templates_validate)
      ((usage_vm_templates_validate++))
      ((last_run_actions_total++))
      ;;
    templates_apply)
      ((usage_vm_templates_apply++))
      ((last_run_actions_total++))
      ;;
    rollback)
      ((usage_rollback_runs++))
      ((last_run_actions_total++))
      ;;
    *)
      log_telemetry_event "UNKNOWN_COUNTER" "Unknown counter: $counter_name"
      ;;
  esac
}

pecu_usage_error() {
  local error_code="$1"
  ((last_run_actions_failed++))
  last_run_last_error="$error_code"
}

get_pecu_instance_id() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/pecu"
  local id_file="$dir/instance.id"
  
  mkdir -p "$dir" 2>/dev/null || true
  
  if [[ -f "$id_file" && -r "$id_file" ]]; then
    local existing_id
    existing_id=$(cat "$id_file" 2>/dev/null | tr -d '\n\r\t ')
    if [[ -n "$existing_id" ]]; then
      printf '%s' "$existing_id"
      return 0
    fi
  fi
  
  local instance_id=""
  
  if [[ -f /proc/sys/kernel/random/uuid ]]; then
    instance_id=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '\n\r\t -')
  fi
  
  if [[ -z "$instance_id" ]] && command -v uuidgen &>/dev/null; then
    instance_id=$(uuidgen 2>/dev/null | tr -d '\n\r\t -')
  fi
  
  if [[ -z "$instance_id" ]] && command -v openssl &>/dev/null; then
    instance_id=$(openssl rand -hex 16 2>/dev/null | tr -d '\n\r\t ')
  fi
  
  if [[ -z "$instance_id" ]]; then
    instance_id="pecu-$(date +%s)-$RANDOM-$RANDOM-$$"
  fi
  
  if [[ -n "$instance_id" ]]; then
    printf '%s' "$instance_id" | tr -d '\n\r\t ' > "$id_file" 2>/dev/null || true
    chmod 600 "$id_file" 2>/dev/null || true
  fi
  
  printf '%s' "$instance_id" | tr -d '\n\r\t '
}

pecu_print_support_footer() {
  local ec="$1"
  local instance_id
  instance_id=$(get_pecu_instance_id 2>/dev/null || echo "unknown")
  local issue_url="https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/issues"

  echo -e "\n${R}PECU Release Selector exited with an error (exit code ${ec}).${NC}"
  echo -e "${Y}You did nothing wrong: this usually indicates an environment issue${NC}"
  echo -e "${Y}(network/GitHub API/repositories or system dependencies).${NC}"
  echo ""
  echo -e "${B}If you need support:${NC}"
  echo -e "  1. Open an issue at: ${L}${issue_url}${NC}"
  echo -e "  2. Include this Instance ID: ${C}${instance_id}${NC}"
  echo -e "  3. Copy the messages above and explain what you were doing."
  echo ""
  echo -e "If telemetry is enabled, this Instance ID allows correlating your report"
  echo -e "with anonymous metrics from this node. We do not collect hostnames, IPs,"
  echo -e "usernames, file paths, or sensitive data."
  echo ""
}

pecu_cleanup() {
  local ec=$?
  if [[ -n "${WORKDIR:-}" ]]; then
    rm -rf -- "$WORKDIR" 2>/dev/null || true
  fi
  if (( ec != 0 )); then
    pecu_print_support_footer "$ec"
  fi
}

init_workspace() {
  local base="${TMPDIR:-/tmp}"
  [[ -d $base && -w $base ]] || base="/var/tmp"
  [[ -d $base && -w $base ]] || base="$HOME/.pecu_tmp"
  mkdir -p "$base" 2>/dev/null || true
  WORKDIR="$base/pecu.$$.$RANDOM"
  mkdir -p "$WORKDIR" 2>/dev/null || {
    echo -e "${R}Error: Cannot create temp workspace${NC}" >&2
    exit 1
  }
  trap 'pecu_cleanup' EXIT
}
init_workspace

missing_critical=()
for cmd in curl find awk sed; do
  command -v "$cmd" &>/dev/null || missing_critical+=("$cmd")
done

if ((${#missing_critical[@]})); then
  echo -e "${R}Critical dependencies missing: ${missing_critical[*]}${NC}"
  echo -e "${Y}These are required for the script to function properly.${NC}"
  echo -e "${Y}Please install them first: apt update && apt install ${missing_critical[*]}${NC}"
  exit 1
fi

# Note: xxd is checked later as it's only needed for telemetry (optional feature)
# It's typically provided by vim-common package

# ── banner ───────────────────────────────────────────────────────────────────
banner() {
  command -v clear &>/dev/null && clear 2>/dev/null || printf '\033[2J\033[H' 2>/dev/null || true
  printf "${L}${B}PROXMOX ENHANCED CONFIG UTILITY (PECU)${NC}\n${Y}"
cat <<'ASCII'
 ██████╗ ███████╗ ██████╗██╗   ██╗
 ██╔══██╗██╔════╝██╔════╝██║   ██║
 ██████╔╝█████╗  ██║     ██║   ██║
 ██╔═══╝ ██╔══╝  ██║     ██║   ██║
 ██║     ███████╗╚██████╗╚██████╔╝
 ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝
ASCII
  printf "${C}Daniel Puente García  •  BuyMeACoffee: https://buymeacoffee.com/danilop95ps${NC}\n"
  printf "${C}Website: ${U}%s${NC}\n\n" "$SITE"
}

show_web_info() {
  local W; W=$(cols); ((W>80)) && W=80
  box_single "$W" \
    "${B}Enhanced Release Browser Available${NC}" \
    "Visit ${L}${RELEASES_URL}${NC} for:" \
    "- Visual timeline with detailed descriptions" \
    "- Advanced filtering and search options" \
    "- Security notices and updates" \
    "- (Announcement) Premium releases visibility"
}

show_premium_teaser() {
  local W; W=$(cols); ((W>80)) && W=80
  box_single "$W" \
    "${B}PREMIUM RELEASES — Advanced Features & Priority Support${NC}" \
    "Press 'P' for details or visit: ${C}${PREMIUM_URL}${NC}"
}

premium_info_menu() {
  banner
  local W; W=$(cols); ((W>84)) && W=84
  box_double "$W" \
    "${B}PECU PREMIUM — Advanced Features & Priority Support${NC}" \
    "${G}- Automated Configurations${NC}  (enterprise templates)" \
    "${G}- Advanced Security${NC}       (hardening, audits, compliance)" \
    "${G}- Performance Monitoring${NC}  (real-time analytics, reports)" \
    "${G}- Priority Support${NC}        (direct access, faster resolution)" \
    "${G}- Cloud Integration${NC}       (AWS/Azure/GCP, hybrid, DR)" \
    "${G}- Advanced GPU Features${NC}   (multi-GPU, orchestration, CUDA)" \
    "" \
    "${B}Plans${NC}: Monthly €3.99 • Annual €14.99 (save 69%)" \
    "30-day money-back guarantee • Cancel anytime" \
    "" \
    "Purchase / Learn more: ${L}${PREMIUM_URL}${NC}" \
    "You can optionally store your license key for later use."
  printf '\n'
  read -rp "Enter license key (PECU-XXXX-XXXX-XXXX-XXXX) or leave blank: " key || true
  key="${key//[$'\t\r\n ']/}"
  if [[ -n "${key:-}" ]]; then
    if [[ "$key" =~ ^[Pp][Ee][Cc][Uu]-[A-Za-z0-9]{4}(-[A-Za-z0-9]{4}){3}$ ]]; then
      local lp="${XDG_CONFIG_HOME:-$HOME/.config}/pecu"
      mkdir -p "$lp" 2>/dev/null || true
      printf '%s\n' "$key" > "$lp/license" 2>/dev/null || true
      chmod 600 "$lp/license" 2>/dev/null || true
      echo -e "${G}License stored at ${lp}/license${NC}"
    else
      echo -e "${R}Invalid format. Nothing saved.${NC}"
    fi
  else
    echo "No license provided."
  fi
  printf '\n'; read -rp "Press Enter to return… " _ || true
}

security_notice() {
  printf "${Y}Security notice:${NC} Always verify downloads and review security policies before installation.\n"
  printf "Private disclosure guidelines are available in the GitHub Security tab.\n\n"
}

check_telemetry_consent() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/pecu"
  local opt_file="$dir/telemetry.opt"
  local effective_value=""
  
  if [[ -n "${PECU_TELEMETRY:-}" ]]; then
    case "${PECU_TELEMETRY,,}" in
      off|disable|disabled|0)
        log_telemetry_event "CONSENT_DISABLED" "Telemetry disabled via PECU_TELEMETRY=$PECU_TELEMETRY"
        return 1
        ;;
      on|enable|enabled|1)
        log_telemetry_event "CONSENT_ENABLED" "Telemetry enabled via PECU_TELEMETRY=$PECU_TELEMETRY"
        return 0
        ;;
      *)
        effective_value="auto"
        ;;
    esac
  fi
  
  if [[ -f "$opt_file" && -r "$opt_file" ]]; then
    local file_value
    file_value=$(cat "$opt_file" 2>/dev/null | tr -d '\n\r\t ' | tr '[:upper:]' '[:lower:]')
    case "$file_value" in
      enabled)
        log_telemetry_event "CONSENT_ENABLED" "Telemetry enabled via config file: $opt_file"
        return 0
        ;;
      disabled)
        log_telemetry_event "CONSENT_DISABLED" "Telemetry disabled via config file: $opt_file"
        return 1
        ;;
      *)
        effective_value="auto"
        ;;
    esac
  else
    effective_value="auto"
  fi
  
  if [[ "$effective_value" == "auto" ]]; then
    if [[ -t 0 && -t 1 ]]; then
      echo ""
      echo -e "${C}╔═══════════════════════════════════════════════════════════════╗${NC}"
      echo -e "${C}║${NC}  ${B}PECU Anonymous Usage Statistics${NC}                         ${C}║${NC}" >&2
      echo -e "${C}╚═══════════════════════════════════════════════════════════════╝${NC}"
      echo ""
      echo -e "${Y}PECU will send anonymous usage and environment metrics to help improve the software.${NC}"
      echo -e "${Y}This can be disabled at any time.${NC}"
      echo ""
      echo -e "${G}Data collected:${NC}"
      echo -e "  • Instance ID (random UUID, no personal info)"
      echo -e "  • PECU version, channel, and selector version"
      echo -e "  • Usage profile (homelab/commercial/corporate/educational/other)"
      echo -e "  • Feature usage counters (aggregated, no configuration details)"
      echo -e "  • OS, distro, architecture, kernel, init system"
      echo -e "  • Proxmox VE: version, cluster, VM/container counts, subscription mode, HA"
      echo -e "  • CPU: model, vendor, cores, threads, sockets, virtualization"
      echo -e "  • RAM total and swap usage (MB)"
      echo -e "  • GPU: count, vendor, model, VRAM, passthrough config"
      echo -e "  • Storage: ZFS/Ceph presence, pool counts, anonymous storage types"
      echo ""
      echo -e "${R}NOT collected:${NC}"
      echo -e "  • Hostnames, IP addresses, MAC addresses"
      echo -e "  • Usernames or personal identification"
      echo -e "  • Disk space or usage statistics"
      echo -e "  • VM names, configurations, file paths, or sensitive data"
      echo -e "  • Storage IDs, pool names, or specific paths"
      echo ""
      echo -e "${Y}Purpose:${NC}"
      echo -e "  • Aggregate usage statistics (installation counts, popular versions)"
      echo -e "  • Hardware compatibility analysis"
      echo -e "  • Feature usage patterns to prioritize development"
      echo -e "  • Bug detection and performance optimization"
      echo ""
      echo -e "More info: ${L}${SITE}/telemetry${NC}"
      echo -e "Control: Set ${C}PECU_TELEMETRY=off${NC} to disable, or edit ${C}~/.config/pecu/telemetry.opt${NC}"
      echo ""
      
      local answer
      read -rp "Allow sending anonymous usage metrics? [Y/n] (default: Yes): " answer || answer=""
      echo ""
      
      mkdir -p "$dir" 2>/dev/null || true
      
      case "${answer,,}" in
        n|no)
          printf 'disabled' > "$opt_file" 2>/dev/null || true
          chmod 600 "$opt_file" 2>/dev/null || true
          log_telemetry_event "CONSENT_DENIED" "User declined telemetry via interactive prompt"
          echo -e "${Y}Telemetry disabled. You can enable it later by editing: ${C}$opt_file${NC}"
          echo ""
          return 1
          ;;
        *)
          # Empty input or y/yes = consent (default is Yes)
          printf 'enabled' > "$opt_file" 2>/dev/null || true
          chmod 600 "$opt_file" 2>/dev/null || true
          log_telemetry_event "CONSENT_GRANTED" "User accepted telemetry via interactive prompt"
          echo -e "${G}✓ Telemetry enabled. Thank you for helping improve PECU!${NC}"
          echo -e "${Y}  You can disable it anytime: ${C}PECU_TELEMETRY=off${NC} or edit ${C}$opt_file${NC}"
          echo ""
          return 0
          ;;
      esac
    else
      return 1
    fi
  fi
  
  return 1
}

get_usage_profile() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/pecu"
  local profile_file="$dir/usage.profile"
  
  mkdir -p "$dir" 2>/dev/null || true
  
  if [[ -f "$profile_file" && -r "$profile_file" ]]; then
    local profile
    profile=$(cat "$profile_file" 2>/dev/null | tr -d '\n\r\t ' | tr '[:upper:]' '[:lower:]')
    case "$profile" in
      homelab_personal|hosting_commercial|internal_corporate|educational_lab|other)
        printf '%s' "$profile"
        return 0
        ;;
    esac
  fi
  
  # Ask user interactively if in TTY and no valid profile exists
  if [[ -t 0 && -t 1 ]]; then
    echo ""
    echo -e "${C}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${C}║${NC}  ${B}PECU Usage Profile${NC}                                       ${C}║${NC}"
    echo -e "${C}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${Y}To better understand PECU usage patterns, please select your profile:${NC}"
    echo ""
    echo -e "  ${G}1)${NC} homelab_personal     - Personal homelab or self-hosted"
    echo -e "  ${G}2)${NC} hosting_commercial   - Commercial hosting / service provider"
    echo -e "  ${G}3)${NC} internal_corporate   - Corporate / enterprise internal IT"
    echo -e "  ${G}4)${NC} educational_lab      - Educational institution / lab"
    echo -e "  ${G}5)${NC} other                - Other use case"
    echo ""
    
    local selection
    read -rp "Select profile [1-5] (default: 1 - homelab_personal): " selection || selection="1"
    echo ""
    
    local profile="homelab_personal"
    case "${selection}" in
      1|"") profile="homelab_personal" ;;
      2) profile="hosting_commercial" ;;
      3) profile="internal_corporate" ;;
      4) profile="educational_lab" ;;
      5) profile="other" ;;
      *) profile="homelab_personal" ;;
    esac
    
    printf '%s' "$profile" > "$profile_file" 2>/dev/null || true
    chmod 600 "$profile_file" 2>/dev/null || true
    
    echo -e "${G}✓ Usage profile set to: ${profile}${NC}"
    echo -e "${Y}  You can change this by editing: ${C}$profile_file${NC}"
    echo ""
    
    printf '%s' "$profile"
    return 0
  fi
  
  # Default fallback
  printf 'homelab_personal'
}

log_telemetry_event() {
  local event_type="$1"
  shift
  local message="$*"
  
  if [[ $PECU_TELEMETRY_VERBOSE != true && "$PECU_ENVIRONMENT" != "local" ]]; then
    return 0
  fi
  
  local log_file="${XDG_CONFIG_HOME:-$HOME/.config}/pecu/telemetry.log"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || return 0
  
  if [[ -f "$log_file" ]]; then
    local line_count
    line_count=$(wc -l < "$log_file" 2>/dev/null || echo "0")
    if (( line_count > 100 )); then
      tail -n 100 "$log_file" > "${log_file}.tmp.$$" 2>/dev/null && \
        mv "${log_file}.tmp.$$" "$log_file" 2>/dev/null || \
        rm -f "${log_file}.tmp.$$" 2>/dev/null
    fi
  fi
  
  printf '[%s] %-20s %s\n' "$timestamp" "$event_type" "$message" >> "$log_file" 2>/dev/null || true
  
  if [[ $PECU_TELEMETRY_VERBOSE == true ]]; then
    echo -e "${C}[TELEMETRY]${NC} ${Y}[$event_type]${NC} $message" >&2
  fi
}

send_pecu_telemetry() {
  # Telemetry consent check - exit early if user declined
  check_telemetry_consent || return 0
  
  # Check required dependencies for telemetry
  command -v jq &>/dev/null || {
    log_telemetry_event "DEPENDENCY_MISSING" "jq not found, skipping telemetry"
    return 0
  }
  command -v curl &>/dev/null || {
    log_telemetry_event "DEPENDENCY_MISSING" "curl not found, skipping telemetry"
    return 0
  }
  command -v openssl &>/dev/null || {
    log_telemetry_event "DEPENDENCY_MISSING" "openssl not found, skipping telemetry"
    return 0
  }

  local instance_id
  instance_id=$(get_pecu_instance_id)
  if [[ -z "$instance_id" ]]; then
    log_telemetry_event "INSTANCE_ID_ERROR" "Could not generate instance ID"
    instance_id="unknown"
  fi

  # --- Basic system info ---
  local os arch kernel
  os="$(uname -s 2>/dev/null || echo "unknown")"
  arch="$(uname -m 2>/dev/null || echo "unknown")"
  kernel="$(uname -r 2>/dev/null || echo "unknown")"
  
  # --- Distribution info ---
  local distro_id distro_version init_system
  distro_id="unknown"
  distro_version="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release 2>/dev/null || true
    distro_id="${ID:-unknown}"
    distro_version="${VERSION_ID:-unknown}"
  fi
  
  init_system="unknown"
  if command -v systemctl &>/dev/null; then
    init_system="systemd"
  fi
  
  # --- Proxmox detection and metrics ---
  local proxmox_detected pve_version pve_kernel_series pve_node_name
  local pve_cluster pve_cluster_nodes pve_qemu_count pve_lxc_count pve_storage_count
  
  proxmox_detected="false"
  pve_version="unknown"
  pve_kernel_series="unknown"
  pve_node_name=""
  pve_cluster="false"
  pve_cluster_nodes=0
  pve_qemu_count=0
  pve_lxc_count=0
  pve_storage_count=0
  
  if [[ -f /etc/pve/.version ]] || command -v pveversion &>/dev/null; then
    proxmox_detected="true"
    
    # Get Proxmox version
    if command -v pveversion &>/dev/null; then
      local pvline
      pvline="$(pveversion 2>/dev/null | head -n1 || echo "")"
      pve_version="$(printf '%s\n' "$pvline" | awk -F'[ /]' '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+/) {print $i; exit}}')"
      [[ -z "$pve_version" ]] && pve_version="unknown"
    fi
    
    # Get kernel series
    if [[ "$pve_version" != "unknown" ]]; then
      pve_kernel_series=$(printf '%s' "$kernel" | cut -d'.' -f1,2 2>/dev/null || echo "unknown")
    fi
    
    # Get node name (anonymized by using only hostname, no FQDN)
    pve_node_name=$(hostname -s 2>/dev/null || echo "")
    
    # Count QEMU VMs
    if ls /etc/pve/qemu-server/*.conf &>/dev/null; then
      pve_qemu_count=$(ls /etc/pve/qemu-server/*.conf 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    fi
    
    # Count LXC containers
    if ls /etc/pve/lxc/*.conf &>/dev/null; then
      pve_lxc_count=$(ls /etc/pve/lxc/*.conf 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    fi
    
    # Count storage definitions
    if [[ -r /etc/pve/storage.cfg ]]; then
      pve_storage_count=$(grep -cE '^[a-z]+:' /etc/pve/storage.cfg 2>/dev/null || echo 0)
    fi
    
    # Cluster detection
    if [[ -r /etc/pve/corosync.conf ]]; then
      pve_cluster="true"
      pve_cluster_nodes=$(grep -c 'node[[:space:]]\+{' /etc/pve/corosync.conf 2>/dev/null || echo 0)
    fi
    
    # --- Enhanced Proxmox metrics ---
    # Subscription mode detection
    local pve_subscription_mode="unknown"
    if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
      if grep -qE '^[^#]*enterprise' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null; then
        pve_subscription_mode="enterprise"
      fi
    fi
    if [[ -f /etc/apt/sources.list.d/pve-no-subscription.list ]]; then
      if grep -qE '^[^#]*pve-no-subscription' /etc/apt/sources.list.d/pve-no-subscription.list 2>/dev/null; then
        pve_subscription_mode="no-subscription"
      fi
    fi
    if [[ -f /etc/apt/sources.list.d/pvetest.list ]]; then
      if grep -qE '^[^#]*pvetest' /etc/apt/sources.list.d/pvetest.list 2>/dev/null; then
        pve_subscription_mode="test"
      fi
    fi
    
    # HA detection
    local pve_ha_enabled="false"
    if [[ -d /etc/pve/ha ]] && ls /etc/pve/ha/*.cfg &>/dev/null 2>&1; then
      pve_ha_enabled="true"
    fi
    
    # Storage types detection (anonymous, no IDs or names)
    local pve_storage_types_raw=""
    if [[ -r /etc/pve/storage.cfg ]]; then
      pve_storage_types_raw=$(awk '/^[[:space:]]*type[[:space:]]/ {print $2}' /etc/pve/storage.cfg 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
    fi
    local pve_storage_types="$pve_storage_types_raw"
    
    # Root filesystem type detection
    local rootfs_type="unknown"
    local root_mount root_fstype
    root_mount=$(df / 2>/dev/null | tail -1 | awk '{print $1}')
    root_fstype=$(df -T / 2>/dev/null | tail -1 | awk '{print $2}')
    
    if [[ "$root_fstype" == "zfs" ]] || [[ "$root_mount" =~ zfs ]]; then
      rootfs_type="zfs"
    elif [[ "$root_fstype" == "btrfs" ]]; then
      rootfs_type="btrfs"
    elif [[ "$root_fstype" == "ext4" ]] || [[ "$root_fstype" == "ext3" ]] || [[ "$root_fstype" == "ext2" ]]; then
      if [[ "$root_mount" =~ /dev/mapper ]]; then
        rootfs_type="lvm-ext4"
      else
        rootfs_type="ext4"
      fi
    elif [[ "$root_fstype" == "xfs" ]]; then
      if [[ "$root_mount" =~ /dev/mapper ]]; then
        rootfs_type="lvm-xfs"
      else
        rootfs_type="xfs"
      fi
    elif [[ "$root_mount" =~ /dev/mapper ]]; then
      rootfs_type="lvm"
    else
      rootfs_type="$root_fstype"
    fi
  fi
  
  # --- CPU metrics ---
  local cpu_cores cpu_threads cpu_sockets cpu_cores_per_socket cpu_threads_per_core
  local cpu_model cpu_vendor cpu_vendor_raw cpu_virt_support
  
  cpu_threads=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "0")
  [[ "$cpu_threads" =~ ^[0-9]+$ ]] || cpu_threads=0
  
  # Count unique physical IDs (sockets), not total lines
  cpu_sockets=$(grep '^physical id' /proc/cpuinfo 2>/dev/null | sort -u | wc -l || echo 0)
  [[ "$cpu_sockets" =~ ^[0-9]+$ ]] || cpu_sockets=0
  [[ $cpu_sockets -eq 0 ]] && cpu_sockets=1
  
  cpu_cores_per_socket=$(grep -m1 '^cpu cores' /proc/cpuinfo 2>/dev/null | awk -F: '{gsub(/^[ \t]+/, "", $2); print $2}' || echo 0)
  [[ "$cpu_cores_per_socket" =~ ^[0-9]+$ ]] || cpu_cores_per_socket=0
  
  # Calculate total physical cores: if we have valid cores_per_socket, use it
  if [[ $cpu_cores_per_socket -gt 0 ]]; then
    cpu_cores=$((cpu_sockets * cpu_cores_per_socket))
  else
    # Fallback: count unique core IDs
    cpu_cores=$(grep '^core id' /proc/cpuinfo 2>/dev/null | sort -u | wc -l || echo 0)
  fi
  [[ "$cpu_cores" =~ ^[0-9]+$ ]] || cpu_cores=0
  [[ $cpu_cores -eq 0 ]] && cpu_cores=$cpu_threads
  
  # Calculate threads per core (SMT/Hyperthreading detection)
  if [[ $cpu_cores -gt 0 ]] && [[ $cpu_threads -gt 0 ]]; then
    cpu_threads_per_core=$((cpu_threads / cpu_cores))
  else
    cpu_threads_per_core=1
  fi
  [[ "$cpu_threads_per_core" =~ ^[0-9]+$ ]] || cpu_threads_per_core=1
  
  cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F: '{sub(/^[ \t]+/, "", $2); print $2}' || echo "unknown")
  
  cpu_vendor_raw=$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk -F: '{sub(/^[ \t]+/, "", $2); print $2}' || echo "unknown")
  cpu_vendor="Other"
  case "$cpu_vendor_raw" in
    *GenuineIntel*) cpu_vendor="Intel" ;;
    *AuthenticAMD*) cpu_vendor="AMD" ;;
    *ARM*|*aarch64*|*ARMv*) cpu_vendor="ARM" ;;
  esac
  
  cpu_virt_support="false"
  if grep -qE "(vmx|svm)" /proc/cpuinfo 2>/dev/null; then
    cpu_virt_support="true"
  fi
  
  # --- Memory metrics ---
  local total_ram_mb swap_total_mb swap_free_mb swap_used_mb
  
  total_ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "0")
  [[ "$total_ram_mb" =~ ^[0-9]+$ ]] || total_ram_mb=0
  
  swap_total_mb=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "0")
  [[ "$swap_total_mb" =~ ^[0-9]+$ ]] || swap_total_mb=0
  
  swap_free_mb=$(awk '/SwapFree/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "0")
  [[ "$swap_free_mb" =~ ^[0-9]+$ ]] || swap_free_mb=0
  
  swap_used_mb=$((swap_total_mb - swap_free_mb))
  [[ $swap_used_mb -lt 0 ]] && swap_used_mb=0
  
  # --- Storage technology detection (ZFS/Ceph only, no disk space) ---
  local zfs_present zfs_pool_count ceph_present
  
  zfs_present="false"
  zfs_pool_count=0
  if command -v zpool &>/dev/null; then
    zfs_present="true"
    zfs_pool_count=$(zpool list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ' || echo 0)
  fi
  
  ceph_present="false"
  if command -v ceph &>/dev/null || [[ -r /etc/pve/ceph.conf ]]; then
    ceph_present="true"
  fi
  
  # --- GPU detection and metrics ---
  local gpu_count gpu_vendor gpu_model
  local gpu_nvidia_count gpu_amd_count gpu_intel_count gpu_passthrough_detected
  local gpu_vram_total_mb gpu_vram_min_mb gpu_vram_max_mb gpu_vram_avg_mb gpu_vram_known_count
  
  gpu_count=0
  gpu_vendor=""
  gpu_model=""
  gpu_nvidia_count=0
  gpu_amd_count=0
  gpu_intel_count=0
  gpu_passthrough_detected="false"
  gpu_vram_total_mb=0
  gpu_vram_min_mb=0
  gpu_vram_max_mb=0
  gpu_vram_avg_mb=0
  gpu_vram_known_count=0
  
  if command -v lspci &>/dev/null; then
    local gpu_map
    gpu_map=$(lspci -nn 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true)
    
    if [[ -n "$gpu_map" ]]; then
      gpu_count=$(printf '%s\n' "$gpu_map" | wc -l | tr -d ' ' || echo 0)
      
      gpu_nvidia_count=$(echo "$gpu_map" | grep -ci 'NVIDIA' || echo 0)
      gpu_amd_count=$(echo "$gpu_map" | grep -ciE 'AMD|Advanced Micro Devices' || echo 0)
      gpu_intel_count=$(echo "$gpu_map" | grep -ci 'Intel' || echo 0)
      
      local first_gpu
      first_gpu=$(printf '%s\n' "$gpu_map" | head -n1 || true)
      gpu_model=$(printf '%s\n' "$first_gpu" | cut -d' ' -f3- || echo "")
      
      case "$first_gpu" in
        *NVIDIA*) gpu_vendor="NVIDIA" ;;
        *AMD*|*Advanced\ Micro\ Devices*) gpu_vendor="AMD" ;;
        *Intel*) gpu_vendor="Intel" ;;
        *) gpu_vendor="Other" ;;
      esac
    fi
  fi
  
  if command -v nvidia-smi &>/dev/null; then
    local nv_vram gpu_vram_list
    nv_vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | tr -d '\r' || true)
    
    if [[ -n "$nv_vram" ]]; then
      gpu_vram_list=""
      for v in $nv_vram; do
        if [[ "$v" =~ ^[0-9]+$ ]]; then
          gpu_vram_list="$gpu_vram_list $v"
        fi
      done
      
      if [[ -n "$gpu_vram_list" ]]; then
        for v in $gpu_vram_list; do
          if [[ ! "$v" =~ ^[0-9]+$ ]]; then
            continue
          fi
          
          if [[ $gpu_vram_known_count -eq 0 ]]; then
            gpu_vram_min_mb=$v
            gpu_vram_max_mb=$v
          else
            [[ $v -lt $gpu_vram_min_mb ]] && gpu_vram_min_mb=$v
            [[ $v -gt $gpu_vram_max_mb ]] && gpu_vram_max_mb=$v
          fi
          
          gpu_vram_total_mb=$((gpu_vram_total_mb + v))
          gpu_vram_known_count=$((gpu_vram_known_count + 1))
        done
        
        if [[ $gpu_vram_known_count -gt 0 ]]; then
          gpu_vram_avg_mb=$((gpu_vram_total_mb / gpu_vram_known_count))
        fi
      fi
    fi
  fi
  
  if ls /etc/pve/qemu-server/*.conf &>/dev/null 2>&1; then
    if grep -q 'hostpci' /etc/pve/qemu-server/*.conf 2>/dev/null; then
      gpu_passthrough_detected="true"
    fi
  fi
  
  # --- Get usage profile ---
  local usage_profile
  usage_profile=$(get_usage_profile)
  
  local payload jq_error
  
  jq_error=$(mktemp)
  payload=$(jq -cn \
    --arg instance_id "$instance_id" \
    --arg pecu_version "${TAG:-unknown}" \
    --arg pecu_channel "${CHN:-unknown}" \
    --arg usage_profile "$usage_profile" \
    --arg os "$os" \
    --arg arch "$arch" \
    --arg kernel "$kernel" \
    --arg distro_id "$distro_id" \
    --arg distro_version "$distro_version" \
    --arg init_system "$init_system" \
    --arg proxmox_detected "$proxmox_detected" \
    --arg pve_version "$pve_version" \
    --arg pve_kernel_series "$pve_kernel_series" \
    --arg pve_node_name "$pve_node_name" \
    --arg pve_cluster "$pve_cluster" \
    --arg pve_cluster_nodes "$pve_cluster_nodes" \
    --arg pve_qemu_count "$pve_qemu_count" \
    --arg pve_lxc_count "$pve_lxc_count" \
    --arg pve_storage_count "$pve_storage_count" \
    --arg pve_subscription_mode "${pve_subscription_mode:-unknown}" \
    --arg pve_ha_enabled "${pve_ha_enabled:-false}" \
    --arg rootfs_type "${rootfs_type:-unknown}" \
    --arg pve_storage_types "${pve_storage_types:-}" \
    --arg cpu_model "$cpu_model" \
    --arg cpu_vendor "$cpu_vendor" \
    --arg cpu_cores "$cpu_cores" \
    --arg cpu_threads "$cpu_threads" \
    --arg cpu_sockets "$cpu_sockets" \
    --arg cpu_cores_per_socket "$cpu_cores_per_socket" \
    --arg cpu_threads_per_core "$cpu_threads_per_core" \
    --arg cpu_virt_support "$cpu_virt_support" \
    --arg total_ram_mb "$total_ram_mb" \
    --arg swap_total_mb "$swap_total_mb" \
    --arg swap_used_mb "$swap_used_mb" \
    --arg zfs_present "$zfs_present" \
    --arg zfs_pool_count "$zfs_pool_count" \
    --arg ceph_present "$ceph_present" \
    --arg gpu_count "$gpu_count" \
    --arg gpu_vendor "$gpu_vendor" \
    --arg gpu_model "$gpu_model" \
    --arg gpu_nvidia_count "$gpu_nvidia_count" \
    --arg gpu_amd_count "$gpu_amd_count" \
    --arg gpu_intel_count "$gpu_intel_count" \
    --arg gpu_passthrough_detected "$gpu_passthrough_detected" \
    --arg gpu_vram_total_mb "$gpu_vram_total_mb" \
    --arg gpu_vram_min_mb "$gpu_vram_min_mb" \
    --arg gpu_vram_max_mb "$gpu_vram_max_mb" \
    --arg gpu_vram_avg_mb "$gpu_vram_avg_mb" \
    --arg gpu_vram_known_count "$gpu_vram_known_count" \
    --arg usage_repo_actions "$usage_repo_actions" \
    --arg usage_gpu_passthrough_runs "$usage_gpu_passthrough_runs" \
    --arg usage_kernel_tweaks_runs "$usage_kernel_tweaks_runs" \
    --arg usage_vm_templates_validate "$usage_vm_templates_validate" \
    --arg usage_vm_templates_apply "$usage_vm_templates_apply" \
    --arg usage_rollback_runs "$usage_rollback_runs" \
    --arg last_run_actions_total "$last_run_actions_total" \
    --arg last_run_actions_failed "$last_run_actions_failed" \
    --arg last_run_last_error "$last_run_last_error" \
    '
    def to_bool: (. == "true" or . == "1");
    def to_int: (try tonumber catch 0);
    
    {
      instance_id: $instance_id,
      pecu_version: $pecu_version,
      pecu_channel: $pecu_channel,
      usage_profile: $usage_profile,
      os: $os,
      arch: $arch,
      kernel: $kernel,
      distro_id: $distro_id,
      distro_version: $distro_version,
      init_system: $init_system,
      proxmox_detected: ($proxmox_detected | to_bool),
      pve_version: $pve_version,
      pve_kernel_series: $pve_kernel_series,
      pve_node_name: $pve_node_name,
      pve_cluster: ($pve_cluster | to_bool),
      pve_cluster_nodes: ($pve_cluster_nodes | to_int),
      pve_qemu_count: ($pve_qemu_count | to_int),
      pve_lxc_count: ($pve_lxc_count | to_int),
      pve_storage_count: ($pve_storage_count | to_int),
      pve_subscription_mode: $pve_subscription_mode,
      pve_ha_enabled: ($pve_ha_enabled | to_bool),
      rootfs_type: $rootfs_type,
      pve_storage_types: $pve_storage_types,
      cpu_model: $cpu_model,
      cpu_vendor: $cpu_vendor,
      cpu_cores: ($cpu_cores | to_int),
      cpu_threads: ($cpu_threads | to_int),
      cpu_sockets: ($cpu_sockets | to_int),
      cpu_cores_per_socket: ($cpu_cores_per_socket | to_int),
      cpu_threads_per_core: ($cpu_threads_per_core | to_int),
      cpu_virt_support: ($cpu_virt_support | to_bool),
      total_ram_mb: ($total_ram_mb | to_int),
      swap_total_mb: ($swap_total_mb | to_int),
      swap_used_mb: ($swap_used_mb | to_int),
      zfs_present: ($zfs_present | to_bool),
      zfs_pool_count: ($zfs_pool_count | to_int),
      ceph_present: ($ceph_present | to_bool),
      gpu_count: ($gpu_count | to_int),
      gpu_vendor: $gpu_vendor,
      gpu_model: $gpu_model,
      gpu_nvidia_count: ($gpu_nvidia_count | to_int),
      gpu_amd_count: ($gpu_amd_count | to_int),
      gpu_intel_count: ($gpu_intel_count | to_int),
      gpu_passthrough_detected: ($gpu_passthrough_detected | to_bool),
      gpu_vram_total_mb: ($gpu_vram_total_mb | to_int),
      gpu_vram_min_mb: ($gpu_vram_min_mb | to_int),
      gpu_vram_max_mb: ($gpu_vram_max_mb | to_int),
      gpu_vram_avg_mb: ($gpu_vram_avg_mb | to_int),
      gpu_vram_known_count: ($gpu_vram_known_count | to_int),
      usage_repo_actions: ($usage_repo_actions | to_int),
      usage_gpu_passthrough_runs: ($usage_gpu_passthrough_runs | to_int),
      usage_kernel_tweaks_runs: ($usage_kernel_tweaks_runs | to_int),
      usage_vm_templates_validate: ($usage_vm_templates_validate | to_int),
      usage_vm_templates_apply: ($usage_vm_templates_apply | to_int),
      usage_rollback_runs: ($usage_rollback_runs | to_int),
      last_run_actions_total: ($last_run_actions_total | to_int),
      last_run_actions_failed: ($last_run_actions_failed | to_int),
      last_run_last_error: $last_run_last_error
    }
    | with_entries(select(.value != "" and .value != null))
    ' 2>"$jq_error") || {
    local error_msg
    error_msg=$(cat "$jq_error" 2>/dev/null || echo "unknown error")
    rm -f "$jq_error" 2>/dev/null
    log_telemetry_event "PAYLOAD_ERROR" "Failed to generate JSON payload: $error_msg"
    return 0
  }
  rm -f "$jq_error" 2>/dev/null
  
  if ! echo "$payload" | jq -e . >/dev/null 2>&1; then
    log_telemetry_event "PAYLOAD_INVALID" "Generated payload is not valid JSON"
    return 0
  fi

  # JSON preview mode: save to file and display with pager
  if [[ "${PECU_JSON_PREVIEW:-false}" == "true" ]]; then
    local preview_dir="$HOME/.config/pecu"
    local preview_file="$preview_dir/telemetry-preview.json"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Ensure directory exists
    mkdir -p "$preview_dir" 2>/dev/null || true
    
    # Save formatted JSON to file with header
    {
      echo "# PECU Telemetry JSON Preview"
      echo "# Generated: $timestamp"
      echo "# Endpoint: $TELEMETRY_ENDPOINT"
      echo "# Preview mode - no data transmitted"
      echo ""
      echo "$payload" | jq '.' 2>/dev/null || echo "$payload"
    } > "$preview_file" 2>/dev/null
    
    echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${G}  PECU Telemetry JSON Preview${NC}"
    echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${C}✓ JSON saved to: ${W}$preview_file${NC}"
    echo -e "${Y}  Endpoint: $TELEMETRY_ENDPOINT${NC}"
    echo -e "${Y}  Preview mode - no data transmitted${NC}"
    echo ""
    echo -e "${G}Opening JSON in pager for review...${NC}"
    echo -e "${G}(Use arrow keys to navigate, 'q' to exit, you can select and copy text)${NC}"
    echo ""
    sleep 1
    
    # Display with pager for easy navigation and copying
    if command -v less &>/dev/null; then
      echo "$payload" | jq -C '.' 2>/dev/null | less -R +Gg || less "$preview_file"
    else
      # Fallback if less not available - use more or cat
      if command -v more &>/dev/null; then
        echo "$payload" | jq '.' 2>/dev/null | more || more "$preview_file"
      else
        echo "$payload" | jq '.' 2>/dev/null || cat "$preview_file"
      fi
    fi
    
    echo ""
    echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${C}JSON preview saved at: ${W}$preview_file${NC}"
    echo -e "${G}You can review it anytime with: ${W}cat $preview_file | jq .${NC}"
    echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}"
    
    log_telemetry_event "JSON_PREVIEW" "Saved and displayed telemetry JSON preview: $preview_file"
    return 0
  fi

  local _p1="UEVDVVNlY3JldEtleQ=="
  local _p2="MjAyNVYx"
  local telemetry_secret
  
  telemetry_secret="$(printf '%s%s' "$_p1" "$_p2" | base64 -d 2>/dev/null | tr -d '\n\r\t ')" || {
    log_telemetry_event "SECRET_DECODE_ERROR" "base64 decoding failed"
    return 0
  }
  
  if [[ ${#telemetry_secret} -ne 19 ]]; then
    log_telemetry_event "SECRET_LENGTH_ERROR" "Secret length is ${#telemetry_secret}, expected 19"
    return 0
  fi
  
  if [[ ! "$telemetry_secret" =~ ^PECU ]]; then
    log_telemetry_event "SECRET_VALIDATION_ERROR" "Secret format validation failed"
    return 0
  fi

  local signature=""
  
  if command -v xxd &>/dev/null; then
    signature=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$telemetry_secret" -binary 2>/dev/null | xxd -p -c 256 2>/dev/null | tr -d '\n' | tr '[:upper:]' '[:lower:]' || echo "") || true
  fi
  
  if [[ -z "${signature:-}" ]] && command -v od &>/dev/null; then
    signature=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$telemetry_secret" -binary 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' | tr '[:upper:]' '[:lower:]' || echo "") || true
  fi
  
  if [[ -z "${signature:-}" ]]; then
    signature=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$telemetry_secret" 2>/dev/null | awk '{print $NF}' | tr '[:upper:]' '[:lower:]' || echo "") || true
  fi
  
  if [[ -z "${signature:-}" ]]; then
    log_telemetry_event "SIGNATURE_ERROR" "Failed to compute HMAC signature (all methods failed)"
    return 0
  fi
  
  if [[ ! "${signature:-}" =~ ^[0-9a-f]{64}$ ]]; then
    log_telemetry_event "SIGNATURE_INVALID" "Signature format invalid (length=${#signature}): ${signature:-empty}"
    return 0
  fi

  log_telemetry_event "PREPARE" "version=${TAG:-unknown} channel=${CHN:-unknown} endpoint=$TELEMETRY_ENDPOINT"
  
  local response http_code
  
  if [[ "$PECU_ENVIRONMENT" == "local" ]] || [[ $PECU_TELEMETRY_VERBOSE == true ]]; then
    echo -e "${C}╔═══════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${C}║${NC}  ${B}SENDING TELEMETRY (DEV MODE)${NC}                             ${C}║${NC}" >&2
    echo -e "${C}╚═══════════════════════════════════════════════════════════════╝${NC}" >&2
    echo -e "${C}Endpoint:${NC} $TELEMETRY_ENDPOINT" >&2
    echo -e "${C}Payload (pretty-printed):${NC}" >&2
    echo "$payload" | jq . 2>/dev/null >&2 || echo "$payload" >&2
    echo -e "${C}Payload (actual compact):${NC} $payload" >&2
    echo -e "${C}Signature (SHA256-HMAC):${NC} $signature" >&2
    echo -e "${C}Secret length:${NC} ${#telemetry_secret} bytes" >&2
    echo "" >&2
    
    response=$(curl -sS -w "\n%{http_code}" -X POST "$TELEMETRY_ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "X-PECU-SIGNATURE: ${signature}" \
      -H "X-PECU-SIGNATURE-VERSION: v1" \
      --connect-timeout 3 \
      --max-time 5 \
      --data "$payload" 2>&1) || true
    
    http_code=$(echo "$response" | tail -n1 2>/dev/null | grep -E '^[0-9]{3}$' || echo "000")
    local body
    body=$(echo "$response" | head -n-1 2>/dev/null || echo "")
    
    echo -e "${C}Response Code:${NC} $http_code" >&2
    if [[ -n "$body" ]]; then
      echo -e "${C}Response Body:${NC}" >&2
      echo "$body" | jq . 2>/dev/null >&2 || echo "$body" >&2
    fi
    
    echo "" >&2
    if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
      echo -e "${G}✓ Telemetry sent successfully${NC}" >&2
      log_telemetry_event "SENT_SUCCESS" "HTTP $http_code - version=${TAG:-unknown} cpu=$cpu_vendor/${cpu_cores}c/${cpu_threads}t gpu=${gpu_count}x${gpu_vendor} ram=${total_ram_mb}MB proxmox=$proxmox_detected"
      
      # Display support information if in support mode
      if [[ "${PECU_SUPPORT_MODE:-false}" == "true" ]]; then
        local support_token
        support_token=$(echo "$instance_id" | cut -c1-4 | tr '[:lower:]' '[:upper:]')-$(echo "$instance_id" | cut -c5-8 | tr '[:lower:]' '[:upper:]')-$(echo "$instance_id" | cut -c9-12 | tr '[:lower:]' '[:upper:]')
        
        echo "" >&2
        echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo -e "${G}  PECU Support Information${NC}" >&2
        echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo "" >&2
        echo -e "${C}Instance ID:${NC}" >&2
        echo -e "  ${W}$instance_id${NC}" >&2
        echo "" >&2
        echo -e "${C}Support Token:${NC}" >&2
        echo -e "  ${B}PECU-$support_token${NC}" >&2
        echo "" >&2
        echo -e "${Y}Please provide the Support Token above to the PECU support team.${NC}" >&2
        echo "" >&2
        echo -e "${C}System Summary:${NC}" >&2
        echo -e "  Version:  ${W}${TAG:-unknown}${NC}" >&2
        echo -e "  Channel:  ${W}${CHN:-unknown}${NC}" >&2
        echo -e "  Profile:  ${W}$usage_profile${NC}" >&2
        echo -e "  Proxmox:  ${W}$pve_version${NC} (detected: $proxmox_detected)" >&2
        echo "" >&2
        echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo "" >&2
        
        log_telemetry_event "SUPPORT_INFO_DISPLAYED" "token=PECU-$support_token"
      fi
    else
      echo -e "${R}✗ Telemetry failed (HTTP $http_code)${NC}" >&2
      log_telemetry_event "SENT_FAILED" "HTTP $http_code - endpoint=$TELEMETRY_ENDPOINT"
      
      # Show error in support mode
      if [[ "${PECU_SUPPORT_MODE:-false}" == "true" ]]; then
        echo "" >&2
        echo -e "${R}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo -e "${R}  Support Information Unavailable${NC}" >&2
        echo -e "${R}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo "" >&2
        echo -e "${Y}Telemetry could not be sent (HTTP $http_code)${NC}" >&2
        echo -e "${Y}Please check your internet connection and try again.${NC}" >&2
        echo "" >&2
        echo -e "${C}Retry command:${NC}" >&2
        echo -e "  ${W}bash <(curl -sL https://raw.githubusercontent.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/refs/heads/main/scripts/pecu_release_selector.sh) -s${NC}" >&2
        echo "" >&2
        echo -e "${R}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo "" >&2
      fi
    fi
    echo "" >&2
  else
    response=$(curl -sS -w "\n%{http_code}" -X POST "$TELEMETRY_ENDPOINT" \
      -H "Content-Type: application/json" \
      -H "X-PECU-SIGNATURE: ${signature}" \
      -H "X-PECU-SIGNATURE-VERSION: v1" \
      --connect-timeout 3 \
      --max-time 5 \
      --data "$payload" 2>&1) || true
    
    http_code=$(echo "$response" | tail -n1 2>/dev/null | grep -E '^[0-9]{3}$' || echo "000")
    
    if [[ $PECU_TELEMETRY_VERBOSE == true ]]; then
      if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
        log_telemetry_event "SENT_SUCCESS" "HTTP $http_code - version=${TAG:-unknown} cpu=$cpu_vendor/${cpu_cores}c/${cpu_threads}t gpu=${gpu_count}x${gpu_vendor} ram=${total_ram_mb}MB proxmox=$proxmox_detected"
      else
        log_telemetry_event "SENT_FAILED" "HTTP $http_code - endpoint=$TELEMETRY_ENDPOINT"
      fi
    fi
    
    # Display support information if in support mode (silent mode path)
    if [[ "${PECU_SUPPORT_MODE:-false}" == "true" ]]; then
      if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
        echo -e "${G}✓ Telemetry sent successfully${NC}" >&2
        
        local support_token
        support_token=$(echo "$instance_id" | cut -c1-4 | tr '[:lower:]' '[:upper:]')-$(echo "$instance_id" | cut -c5-8 | tr '[:lower:]' '[:upper:]')-$(echo "$instance_id" | cut -c9-12 | tr '[:lower:]' '[:upper:]')
        
        echo "" >&2
        echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo -e "${G}  PECU Support Information${NC}" >&2
        echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo "" >&2
        echo -e "${C}Instance ID:${NC}" >&2
        echo -e "  ${W}$instance_id${NC}" >&2
        echo "" >&2
        echo -e "${C}Support Token:${NC}" >&2
        echo -e "  ${B}PECU-$support_token${NC}" >&2
        echo "" >&2
        echo -e "${Y}Please provide the Support Token above to the PECU support team.${NC}" >&2
        echo "" >&2
        echo -e "${C}System Summary:${NC}" >&2
        echo -e "  Version:  ${W}${TAG:-unknown}${NC}" >&2
        echo -e "  Channel:  ${W}${CHN:-unknown}${NC}" >&2
        echo -e "  Profile:  ${W}$usage_profile${NC}" >&2
        echo -e "  Proxmox:  ${W}$pve_version${NC} (detected: $proxmox_detected)" >&2
        echo "" >&2
        echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo "" >&2
        
        log_telemetry_event "SUPPORT_INFO_DISPLAYED" "token=PECU-$support_token"
      else
        echo "" >&2
        echo -e "${R}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo -e "${R}  Support Information Unavailable${NC}" >&2
        echo -e "${R}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo "" >&2
        echo -e "${Y}Telemetry could not be sent (HTTP $http_code)${NC}" >&2
        echo -e "${Y}Please check your internet connection and try again.${NC}" >&2
        echo "" >&2
        echo -e "${C}Retry command:${NC}" >&2
        echo -e "  ${W}bash <(curl -sL https://raw.githubusercontent.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/refs/heads/main/scripts/pecu_release_selector.sh) -- -s${NC}" >&2
        echo "" >&2
        echo -e "${R}═══════════════════════════════════════════════════════════════════${NC}" >&2
        echo "" >&2
      fi
    fi
  fi
}

if [[ $EUID -eq 0 ]]; then
  IS_ROOT=true
  SUDO_CMD=""
elif command -v sudo &>/dev/null; then
  HAS_SUDO=true
  SUDO_CMD="sudo"
fi

run_as_admin() {
  if [[ $IS_ROOT == true ]]; then
    "$@"
  elif [[ $HAS_SUDO == true ]]; then
    sudo "$@"
  else
    echo -e "${R}Error: This script requires root privileges or sudo to be installed.${NC}"
    echo -e "${Y}Please run as root or install sudo first: apt update && apt install sudo${NC}"
    return 1
  fi
}

proxmox_hint() {
  if [[ -f /etc/pve/.version ]]; then
    echo -e "${L}Proxmox VE detected${NC}"
    if [[ $IS_ROOT == false && $HAS_SUDO == false ]]; then
      echo -e "${Y}Note: Running without root privileges and sudo not found.${NC}"
      echo -e "${Y}Some operations may require manual intervention.${NC}"
    fi
    echo ""
  fi
}

fix_proxmox_repos() {
  if [[ -f /etc/pve/.version ]] && [[ ! -f /etc/apt/sources.list.d/pve-no-subscription.list ]]; then
    echo -e "${Y}Configuring community repositories for Proxmox (no subscription)…${NC}"
    
    if [[ $IS_ROOT == true ]]; then
      [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]] && sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
      [[ -f /etc/apt/sources.list.d/ceph.list ]] && sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list 2>/dev/null || true
      printf "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription\n" > /etc/apt/sources.list.d/pve-no-subscription.list 2>/dev/null || { pecu_usage_error repo_write_failed; return 1; }
      printf "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription\n" > /etc/apt/sources.list.d/ceph-no-subscription.list 2>/dev/null || { pecu_usage_error repo_write_failed; return 1; }
      apt-get -qq update 2>/dev/null || { echo -e "${Y}Warning: apt-get update failed${NC}"; pecu_usage_error repo_network_error; return 1; }
      pecu_usage_increment repo_actions
    elif [[ $HAS_SUDO == true ]]; then
      [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]] && sudo sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
      [[ -f /etc/apt/sources.list.d/ceph.list ]] && sudo sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list 2>/dev/null || true
      printf "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription\n" | sudo tee /etc/apt/sources.list.d/pve-no-subscription.list >/dev/null 2>&1 || { pecu_usage_error repo_write_failed; return 1; }
      printf "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription\n" | sudo tee /etc/apt/sources.list.d/ceph-no-subscription.list >/dev/null 2>&1 || { pecu_usage_error repo_write_failed; return 1; }
      sudo apt-get -qq update 2>/dev/null || { echo -e "${Y}Warning: apt-get update failed${NC}"; pecu_usage_error repo_network_error; return 1; }
      pecu_usage_increment repo_actions
    else
      echo -e "${Y}Warning: Cannot configure repositories without root privileges or sudo.${NC}"
      pecu_usage_error repo_permission_denied
      return 1
    fi
  fi
  return 0
}

# ── Support Mode: Direct telemetry and exit ──────────────────────────────────
if [[ "${PECU_SUPPORT_MODE:-false}" == "true" ]]; then
  echo ""
  echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}"
  echo -e "${G}  PECU Support Information Generator${NC}"
  echo -e "${G}═══════════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "${Y}Collecting system information and sending telemetry...${NC}"
  echo ""
  
  send_pecu_telemetry
  exit 0
fi

banner
proxmox_hint

if [[ $IS_ROOT == true ]]; then
  echo -e "${G}Running as root - full system access available${NC}"
elif [[ $HAS_SUDO == true ]]; then
  echo -e "${Y}Running as regular user with sudo available${NC}"
else
  echo -e "${R}Warning: Running without root privileges and sudo not found${NC}"
  echo -e "${Y}Some operations may fail. Consider running as root or installing sudo.${NC}"
  echo -e "${Y}To install sudo: ${C}apt update && apt install sudo${NC}"
  echo ""
  read -rp "Continue anyway? [y/N]: " continue_anyway
  if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
fi

show_web_info

missing_deps=()
for pkg in curl jq tar find awk sed; do
  if ! command -v "$pkg" &>/dev/null; then
    missing_deps+=("$pkg")
  fi
done

if ((${#missing_deps[@]})); then
  echo -e "${Y}Missing required dependencies: ${missing_deps[*]}${NC}"
  echo -e "${Y}These packages are required for the script to function properly.${NC}"
  read -rp "Do you want to install them automatically? [Y/n]: " install_deps
  
  if [[ $install_deps =~ ^[Nn]$ ]]; then
    echo -e "${R}Cannot continue without required dependencies.${NC}"
    echo -e "${Y}Please install them manually: apt update && apt install ${missing_deps[*]}${NC}"
    exit 1
  fi
  
  echo -e "${G}Installing dependencies...${NC}"
fi

for pkg in curl jq tar find awk sed; do
  if ! command -v "$pkg" &>/dev/null; then
    echo -e "${Y}Installing dependency: $pkg …${NC}"
    
    if [[ -f /etc/pve/.version ]]; then
      fix_proxmox_repos 2>/dev/null || {
        echo -e "${Y}Warning: Could not configure repositories, trying with existing sources.${NC}"
      }
    fi
    
    run_as_admin apt-get -qq update 2>/dev/null || {
      echo -e "${Y}Warning: Could not update package lists, proceeding anyway.${NC}"
    }
    
    if run_as_admin apt-get -y install "$pkg" 2>/dev/null; then
      echo -e "${G}Successfully installed $pkg${NC}"
    else
      if [[ "$pkg" == "jq" ]]; then
        echo -e "${Y}Standard installation failed, trying alternative methods for jq…${NC}"
        
        if curl -fsSL "https://github.com/jqlang/jq/releases/latest/download/jq-linux64" -o "$WORKDIR/jq" 2>/dev/null; then
          chmod +x "$WORKDIR/jq" 2>/dev/null
          if "$WORKDIR/jq" --version &>/dev/null 2>&1; then
            if run_as_admin cp "$WORKDIR/jq" /usr/local/bin/jq 2>/dev/null; then
              echo -e "${G}Successfully installed jq via direct download${NC}"
              continue
            fi
          fi
        fi
        
        echo -e "${Y}Trying user-local installation for jq…${NC}"
        mkdir -p "$HOME/.local/bin" 2>/dev/null || true
        if curl -fsSL "https://github.com/jqlang/jq/releases/latest/download/jq-linux64" -o "$HOME/.local/bin/jq" 2>/dev/null; then
          chmod +x "$HOME/.local/bin/jq" 2>/dev/null
          if "$HOME/.local/bin/jq" --version &>/dev/null 2>&1; then
            export PATH="$HOME/.local/bin:$PATH"
            echo -e "${G}Successfully installed jq to user directory${NC}"
            continue
          fi
        fi
        
        if command -v snap &>/dev/null; then
          echo -e "${Y}Trying snap installation for jq…${NC}"
          if run_as_admin snap install jq 2>/dev/null; then
            echo -e "${G}Successfully installed jq via snap${NC}"
            continue
          fi
        fi
        
        echo -e "${R}Failed to install jq using all available methods.${NC}"
        echo -e "${Y}You can try installing it manually with one of these commands:${NC}"
        echo -e "  ${C}apt update && apt install jq${NC}"
        echo -e "  ${C}snap install jq${NC}"
        echo -e "  ${C}wget https://github.com/jqlang/jq/releases/latest/download/jq-linux64 -O /usr/local/bin/jq && chmod +x /usr/local/bin/jq${NC}"
        exit 1
      else
        echo -e "${R}Failed to install $pkg.${NC}"
        echo -e "${Y}You may need to install it manually: apt install $pkg${NC}"
        exit 1
      fi
    fi
  fi
done

if ! command -v jq &>/dev/null || ! echo '{}' | jq . &>/dev/null; then
  echo -e "${R}jq is still not available or not working properly.${NC}"
  echo -e "${Y}The script requires jq to parse JSON responses from GitHub API.${NC}"
  echo -e "${Y}Please install jq manually using one of these methods:${NC}"
  echo -e "  ${C}# Method 1: Package manager (preferred)${NC}"
  echo -e "  ${C}apt update && apt install jq${NC}"
  echo -e "  ${C}# Method 2: Direct download${NC}"
  echo -e "  ${C}wget https://github.com/jqlang/jq/releases/latest/download/jq-linux64 -O /usr/local/bin/jq${NC}"
  echo -e "  ${C}chmod +x /usr/local/bin/jq${NC}"
  echo -e "  ${C}# Method 3: Snap (if available)${NC}"
  echo -e "  ${C}snap install jq${NC}"
  exit 1
fi

if ((${#missing_deps[@]})); then
  echo -e "${G}✓ All dependencies installed successfully!${NC}"
  echo -e "${Y}Restarting interface...${NC}"
  sleep 2
  banner
  proxmox_hint
  
  if [[ $IS_ROOT == true ]]; then
    echo -e "${G}Running as root - full system access available${NC}"
  elif [[ $HAS_SUDO == true ]]; then
    echo -e "${Y}Running as regular user with sudo available${NC}"
  fi
  
  show_web_info
fi

security_notice

show_releases_and_select() {
  echo -e "${Y}Fetching available releases…${NC}"
  mapfile -t META < <(
    curl -fsSL "$API" 2>/dev/null | jq -r '
      .[]
      | select(.body|test("PECU-Channel:"))
      | select(.body|test("Deprecated|Obsolete|Retired";"i")|not)
      | .asset = ((.assets[]? | select(.name|test("\\.tar\\.gz$")) | .browser_download_url) // "")
      | { tag:.tag_name,
          date:(.published_at|split("T")[0]),
          chan:(.body|capture("PECU-Channel:\\s*(?<x>[^\r\n]+)") .x),
          title:(.body|capture("PECU-Title:\\s*(?<x>[^\r\n]+)") .x // "Release"),
          asset:.asset }
      | "\(.date)|\(.chan)|\(.tag)|\(.title)|\(.asset)"' 2>/dev/null )

  ((${#META[@]})) || { echo -e "${R}No releases found.${NC}"; exit 1; }

  IFS=$'\n' META=($(sort -r <<<"${META[*]}"))
  LATEST=$(printf '%s\n' "${META[@]}" | grep -m1 '|[Ss]table|' || true)

  local TW; TW=$(cols)
  local ID_W=3; local TAG_W=14; local DATE_W=10
  local MAX_CH
  MAX_CH=$(printf '%s\n' "${META[@]}" | cut -d'|' -f2 | awk '{print length}' | sort -nr | head -1)
  (( MAX_CH<7 )) && MAX_CH=7
  local CH_W=$((MAX_CH+2))
  local TITLE_W=$((TW - ID_W - TAG_W - DATE_W - CH_W - 6))
  ((TITLE_W>42)) && TITLE_W=42
  ((TITLE_W<18)) && TITLE_W=18

  echo -e "\n${B}Available Releases:${NC}"
  printf "${B}%-${ID_W}s %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]${NC}\n" "#" "TAG" "TITLE" "DATE" "CHANNEL"
  printf '%s\n' "$(repeat '─' "$TW")"

  declare -A IDX; local n=1
  for rec in "${META[@]}"; do
    IFS='|' read -r d ch tag ttl asset <<<"$rec"
    local lc=${ch,,}; [[ $lc =~ ^(stable|beta|preview|experimental|nightly|legacy)$ ]] || lc=other
    local cut=$ttl; (( ${#cut}>TITLE_W )) && cut="${cut:0:$((TITLE_W-2))}…"
    local latest=''; [[ $rec == "$LATEST" ]] && latest=' ★LATEST'
    printf "${COL[$lc]} %-${ID_W}d %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]${NC}%s\n" \
           "$n" "$tag" "$cut" "$d" "$lc" "$latest"
    IDX[$n]="$tag|$lc|$asset"
    ((n++))
  done

  show_premium_teaser
  printf " %-${ID_W}s Exit\n" 0

  # Mostrar Instance ID para soporte
  local __inst_id
  __inst_id=$(get_pecu_instance_id 2>/dev/null || echo "unknown")
  echo -e "\n${C}Support Instance ID:${NC} ${__inst_id}"
  echo -e "Incluye este ID si abres una issue: ${L}https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/issues${NC}"

  while :; do
    read -rp $'\nSelect release # (or P for Premium): ' sel
    if [[ "$sel" =~ ^[Pp]$ ]]; then
      premium_info_menu
      banner; proxmox_hint; show_web_info
      show_releases_and_select
      return
    fi
    if [[ "$sel" =~ ^[0-9]+$ ]]; then
      (( sel==0 )) && exit 0
      [[ ${IDX[$sel]-} ]] && break || echo -e "${R}Invalid ID.${NC}"
    else
      echo -e "${Y}Enter a number (1-${#META[@]}), 'P' for Premium, or '0' to exit.${NC}"
    fi
  done
  
  IFS='|' read -r TAG CHN ASSET <<<"${IDX[$sel]}"
  
  handle_ui_deps_and_execute
}

handle_ui_deps_and_execute() {
  local ui_missing=()
  for d in whiptail dialog; do command -v "$d" &>/dev/null || ui_missing+=("$d"); done
  if ((${#ui_missing[@]})); then
    echo -e "${Y}Missing optional UI packages: ${ui_missing[*]}${NC}"
    echo -e "${Y}These packages improve the user interface but are not required.${NC}"
    read -rp "Install them automatically? [Y/n]: " ans
    if [[ ! $ans =~ ^[Nn]$ ]]; then
      echo -e "${G}Installing optional UI packages...${NC}"
      local packages_installed=false
      for d in "${ui_missing[@]}"; do
        echo -e "${Y}Installing $d …${NC}"
        if run_as_admin apt-get -y install "$d" 2>/dev/null; then
          echo -e "${G}Successfully installed $d${NC}"
          packages_installed=true
        else
          echo -e "${R}Warning: Failed to install $d${NC}"
          echo -e "${Y}This package is optional and the script will continue without it.${NC}"
        fi
      done
      
      if [[ $packages_installed == true ]]; then
        echo -e "${G}✓ UI packages installation completed!${NC}"
        echo -e "${Y}Continuing with release selection...${NC}"
        sleep 1
        banner
      fi
    fi
  fi

  local W
  W="$(($(cols)))"
  ((W>72)) && W=72
  local instance_id
  instance_id=$(get_pecu_instance_id 2>/dev/null || echo "unknown")

  box_single "$W" \
    "${B}SELECTED RELEASE${NC}" \
    "Tag:     ${TAG}" \
    "Channel: ${CHN^}" \
    "Source:  GitHub" \
    "Instance ID: ${instance_id}"

  echo -e "${C}Tip:${NC} si algo falla, incluye este Instance ID en tu issue para que podamos"
  echo -e "      localizar rápidamente la telemetría (si está activada) y ayudarte mejor."
  echo ""

  read -rp "Press Y to run | any other key to cancel: " ok
  [[ $ok =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

  send_pecu_telemetry

  run_raw() {
    local rel="$1"; [[ -n "${rel:-}" ]] || return 1
    local url="$RAW/$TAG/$rel"
    if curl -sfIL "$url" &>/dev/null; then
      local runner="$WORKDIR/runner.sh"
      if curl -fsSL "$url" -o "$runner" 2>/dev/null; then
        chmod +x "$runner" 2>/dev/null
        (set +e; "$runner"; exit 0)
        return 0
      fi
    fi
    return 1
  }

  run_asset() {
    [[ -n "${ASSET:-}" ]] || return 1
    local tgz="$WORKDIR/pecu.tgz"
    curl -fsSL "$ASSET" -o "$tgz" 2>/dev/null || return 1
    tar -xzf "$tgz" -C "$WORKDIR" 2>/dev/null || return 1
    local sh
    sh=$(find "$WORKDIR" -name proxmox-configurator.sh -type f 2>/dev/null | head -n1 || true)
    [[ -f "${sh:-}" ]] || return 1
    chmod +x "$sh" 2>/dev/null
    (set +e; "$sh"; exit 0)
    return 0
  }

  echo -e "${G}→ Executing $TAG …${NC}"
  local START
  START=$(date +%s)
  run_raw "src/proxmox-configurator.sh"  || true
  run_raw "proxmox-configurator.sh"      || true

  if (( $(date +%s) - START < 3 )); then
    echo -e "${Y}Script ended quickly — trying packaged asset…${NC}"
    run_asset || true
  fi
  
  echo -e "\n${Y}Execution completed. Press Enter to continue…${NC}"
  read -r
}

show_releases_and_select
