#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#        ██████╗ ███████╗ ██████╗██╗   ██╗
#        ██╔══██╗██╔════╝██╔════╝██║   ██║
#        ██████╔╝█████╗  ██║     ██║   ██║
#        ██╔═══╝ ██╔══╝  ██║     ██║   ██║
#        ██║     ███████╗╚██████╗╚██████╔╝
#        ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝ 
# -----------------------------------------------------------------------------
# PECU Release Selector — Whiptail + Fancy ASCII Fallback (v2.0)
# By Daniel Puente García — BuyMeACoffee: https://buymeacoffee.com/danilop95ps
# Version: 2.0 — 2025-05-14
# -----------------------------------------------------------------------------

set -euo pipefail

### === CONFIGURATION ===
# Repo info
GITHUB_REPO="Danilop95/Proxmox-Enhanced-Configuration-Utility"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}"
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
CONF_FILE="${SCRIPT_DIR}/versions.conf"
FALLBACK_SCRIPT="${SCRIPT_DIR}/pecu_release_selector_old.sh"

# Default colors (ANSI escapes)
RED='\e[0;31m'; GREEN='\e[0;32m'; BLUE='\e[0;34m'; YELLOW='\e[0;33m'; NC='\e[0m'

# Whiptail menu sizing (override by exporting these env vars if desired)
: "${MENU_HEIGHT:=18}"
: "${MENU_WIDTH:=70}"
: "${MENU_CHOICE_HEIGHT:=10}"

### === DEPENDENCY CHECK ===
for cmd in whiptail curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}Warning:${NC} '$cmd' not found. Falling back to classic ASCII menu."
    bash "$FALLBACK_SCRIPT"
    exit 0
  fi
done

### === SPINNER GAUGE ===
launch_spinner() {
  {
    for i in {0..100..10}; do
      echo "$i"
      echo "XXX"
      echo "Initializing PECU Selector…"
      echo "XXX"
      sleep 0.1
    done
  } | whiptail --gauge "Please wait…" 6 60 0
}

### === READ VERSIONS.CONF ===
# Format per line:
# tag|channel|label|description|published_date|[optional]tag_color|[optional]label_color
read_versions() {
  mapfile -t raw_lines < <(grep -Ev '^\s*#|^\s*$' "$CONF_FILE" 2>/dev/null || true)
  [[ ${#raw_lines[@]} -gt 0 ]]
}

### === BUILD WHIPTAIL MENU ===
build_menu() {
  TAGS=(); MENU_ITEMS=()
  for idx in "${!raw_lines[@]}"; do
    IFS='|' read -r tag chan lab desc pub tcol lcol <<<"${raw_lines[idx]}"
    # fallback to defaults if colors not specified
    tag_color="${tcol:-$BLUE}"
    lab_color="${lcol:-$GREEN}"
    TAGS+=("$tag")
    # Build menu entry string (colors only show if terminal supports ANSI in whiptail)
    entry="$tag_color$tag${NC}\n[$chan] ${lab_color}${lab^^}${NC}\n$desc\nPublished: $pub"
    MENU_ITEMS+=("$((idx+1))" "$entry")
  done
  MENU_ITEMS+=("0" "Exit")
}

### === FALLBACK ASCII MENU ===
old_menu() {
  clear
  echo -e "${BLUE}===============================================${NC}"
  echo -e "${BLUE}  PROXMOX ENHANCED CONFIG UTILITY (PECU)       ${NC}"
  echo -e "${BLUE}===============================================${NC}"
  echo -e "${GREEN}          Classic Release Selector             ${NC}"
  echo -e "${YELLOW}By Daniel Puente García — BuyMeACoffee: https://buymeacoffee.com/danilop95ps${NC}"
  echo
  echo -e "${YELLOW}Fetching releases via GitHub API...${NC}"
  mapfile -t releases < <(curl -sL "$API_URL" \
    | jq -r '.[] | "\(.tag_name) | \(.prerelease) | \(.published_at)"')
  if [[ ${#releases[@]} -eq 0 ]]; then
    echo -e "${RED}Error:${NC} No releases found."; exit 1
  fi

  echo -e "\n${GREEN}Choose a PECU version:${NC}"
  echo "-----------------------------------"
  local idx=1 rec=-1
  for rel in "${releases[@]}"; do
    IFS='|' read -r tag pre pub <<<"$rel"; pub="${pub//\"/}"
    if [[ "$pre" == "false" && rec -eq -1 ]]; then rec=$idx; fi
    if [[ "$pre" == "true" ]]; then
      echo -e "  ${YELLOW}${idx}) ${tag} (Pre-release)${NC} - $pub"
    else
      if [[ $idx -eq $rec ]]; then
        echo -e "  ${GREEN}${idx}) ${tag} (Stable) [RECOMMENDED]${NC} - $pub"
      else
        echo -e "  ${GREEN}${idx}) ${tag} (Stable)${NC} - $pub"
      fi
    fi
    ((idx++))
  done
  echo -e "  ${YELLOW}0) Exit${NC}"
  echo "-----------------------------------"
  read -rp $'\nEnter choice [0-'$((idx-1))']: ' choice
  if [[ "$choice" == "0" ]]; then
    echo -e "${YELLOW}Exiting.${NC}"; exit 0
  fi
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice >= idx )); then
    echo -e "${RED}Invalid selection.${NC}"; exit 1
  fi
  sel="${releases[$((choice-1))]}"
  tag="$(echo "$sel" | cut -d'|' -f1 | xargs)"
  echo -e "\nSelected: ${BLUE}${tag}${NC}"
  read -rp "Proceed to execute? (y/N): " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    bash <(curl -sL "${RAW_BASE}/${tag}/src/proxmox-configurator.sh")
    exit $?
  fi
  exit 0
}

### === MAIN FLOW ===
main() {
  launch_spinner

  if read_versions; then
    build_menu
    CHOICE=$(whiptail \
      --backtitle "PECU Release Selector — By Danilop95" \
      --title "Select a PECU Version" \
      --menu "Use ↑/↓ to navigate, Enter to select.  ESC to fallback." \
      "${MENU_HEIGHT}" "${MENU_WIDTH}" "${MENU_CHOICE_HEIGHT}" \
      "${MENU_ITEMS[@]}" \
      3>&1 1>&2 2>&3) || {
        echo -e "${YELLOW}Falling back to classic menu...${NC}"
        old_menu
        exit 0
      }

    if [[ "$CHOICE" == "0" ]]; then
      exit 0
    fi

    index=$((CHOICE-1))
    tag="${TAGS[index]}"

    whiptail --backtitle "Confirm Run" \
      --title "PECU ${tag}" \
      --msgbox "You selected:\n\n  Tag: ${tag}\n\nProceed to execute?" 10 50

    if whiptail --yesno "Run PECU ${tag} now?" 8 50; then
      bash <(curl -fsL "${RAW_BASE}/${tag}/src/proxmox-configurator.sh")
      exit $?
    fi
    exit 0
  else
    echo -e "${YELLOW}No versions.conf found. Using classic menu.${NC}"
    old_menu
  fi
}

main
