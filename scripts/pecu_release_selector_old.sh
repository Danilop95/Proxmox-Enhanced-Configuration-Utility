#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#        ██████╗ ███████╗ ██████╗██╗   ██╗
#        ██╔══██╗██╔════╝██╔════╝██║   ██║
#        ██████╔╝█████╗  ██║     ██║   ██║
#        ██╔═══╝ ██╔══╝  ██║     ██║   ██║
#        ██║     ███████╗╚██████╗╚██████╔╝
#        ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝ 
# -----------------------------------------------------------------------------
# PECU Release Selector — Whiptail + Fancy ASCII Fallback
# By Daniel Puente García — BuyMeACoffee: https://buymeacoffee.com/danilop95ps
# Version: 1.1 — 2025-05-14
# -----------------------------------------------------------------------------

set -euo pipefail

# Color definitions
RED='\e[0;31m'; GREEN='\e[0;32m'; BLUE='\e[0;34m'; YELLOW='\e[0;33m'; NC='\e[0m'

GITHUB_REPO="Danilop95/Proxmox-Enhanced-Configuration-Utility"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}"
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases"
CONF_FILE="$(dirname "$0")/versions.conf"

# Ensure required commands
for cmd in whiptail curl jq; do
  command -v "$cmd" &>/dev/null || { 
    echo -e "${RED}Error:${NC} '$cmd' is not installed. Please install it and retry."; exit 1; 
  }
done

# -----------------------------------------------------------------------------
# Spinner gauge during initialization
# -----------------------------------------------------------------------------
launch_spinner() {
  {
    for i in {0..100..10}; do
      echo "$i"
      echo "XXX"
      echo "Launching PECU Version Selector…"
      echo "XXX"
      sleep 0.1
    done
  } | whiptail --gauge "Initializing…" 6 60 0
}

# -----------------------------------------------------------------------------
# Read versions.conf (skip comments/blank)
# -----------------------------------------------------------------------------
read_versions() {
  mapfile -t lines < <(grep -Ev '^\s*#|^\s*$' "$CONF_FILE" 2>/dev/null || true)
  [[ ${#lines[@]} -gt 0 ]]
}

# -----------------------------------------------------------------------------
# Fancy ASCII fallback menu (colored)
# -----------------------------------------------------------------------------
old_menu() {
  clear
  echo -e "${BLUE}=================================================${NC}"
  echo -e "${BLUE}  PROXMOX ENHANCED CONFIG UTILITY (PECU)        ${NC}"
  echo -e "${BLUE}=================================================${NC}"
  echo -e "${GREEN}          Version Selector (Fallback Mode)       ${NC}"
  echo -e "${YELLOW}By Daniel Puente García — BuyMeACoffee: https://buymeacoffee.com/danilop95ps${NC}"
  echo
  echo -e "${YELLOW}Fetching releases...${NC}"
  mapfile -t releases < <(curl -sL "$API_URL" \
    | jq -r '.[] | "\(.tag_name) | \(.prerelease) | \(.published_at)"')
  if [[ ${#releases[@]} -eq 0 ]]; then
    echo -e "${RED}Error:${NC} No releases found."; exit 1
  fi

  echo -e "\n${GREEN}Choose a PECU version:${NC}"
  echo "-----------------------------------"
  local idx=1 rec=-1
  for rel in "${releases[@]}"; do
    IFS='|' read -r tag pre pub <<<"$rel"
    pub=$(echo "$pub" | xargs)
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

  while true; do
    read -rp $'\nEnter choice [0-'$((idx-1))']: ' choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=0 && choice<idx )); then
      [[ "$choice" -eq 0 ]] && echo -e "${YELLOW}Exiting.${NC}" && exit 0
      sel="${releases[$((choice-1))]}"
      tag=$(echo "$sel" | cut -d'|' -f1 | xargs)
      echo -e "\nSelected: ${BLUE}${tag}${NC}"
      read -rp "Proceed to execute? (y/N): " yn
      [[ "$yn" =~ ^[Yy] ]] && \
        bash <(curl -sL "${RAW_BASE}/${tag}/src/proxmox-configurator.sh") && exit 0 || exit 1
    else
      echo -e "${RED}Invalid selection.${NC}"
    fi
  done
}

# -----------------------------------------------------------------------------
# Build Whiptail menu from versions.conf
# -----------------------------------------------------------------------------
build_menu() {
  TAGS=(); CHANS=(); LABS=(); DESCS=(); PUBS=(); MENU=()
  for idx in "${!lines[@]}"; do
    IFS='|' read -r tag chan lab desc pub <<<"${lines[idx]}"
    TAGS+=("$tag"); CHANS+=("$chan"); LABS+=("$lab")
    DESCS+=("$desc"); PUBS+=("$pub")
    MENU+=("$((idx+1))" "$tag [${lab^^}]\n ${desc}")
  done
  MENU+=("0" "Exit")
}

# -----------------------------------------------------------------------------
# Main flow
# -----------------------------------------------------------------------------
main() {
  launch_spinner
  if read_versions; then
    build_menu
    while true; do
      CHOICE=$(whiptail \
        --backtitle "PECU Version Selector — By Daniel Puente García" \
        --title "Select a PECU Version" \
        --menu "Channels available: stable | prerelease | beta | rc\n\nUse ↑/↓ to navigate, Enter to select." \
        18 70 10 "${MENU[@]}" 3>&1 1>&2 2>&3)

      (( $? != 0 )) && exit 0
      [[ "$CHOICE" == "0" ]] && exit 0

      idx=$((CHOICE-1))
      tag=${TAGS[idx]}; chan=${CHANS[idx]}; lab=${LABS[idx]}; desc=${DESCS[idx]}; pub=${PUBS[idx]}

      whiptail --backtitle "PECU Version Selector" \
        --title "Confirm: ${tag}" \
        --msgbox "Tag       : ${tag}\nChannel   : ${chan}\nLabel     : ${lab}\nPublished : ${pub}\n\n${desc}\n\nProceed to execute?" \
        14 64

      if whiptail --yesno "Run PECU ${tag} now?" 8 50; then
        bash <(curl -fsL "${RAW_BASE}/${tag}/src/proxmox-configurator.sh")
        exit $?
      fi
    done
  else
    whiptail --title "Notice" --msgbox "No versions.conf found.\nFalling back to ASCII menu." 8 60
    old_menu
  fi
}

main
