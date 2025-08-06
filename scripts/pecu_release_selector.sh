#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#        ██████╗ ███████╗ ██████╗██╗   ██╗
#        ██╔══██╗██╔════╝██╔════╝██║   ██║
#        ██████╔╝█████╗  ██║     ██║   ██║
#        ██╔═══╝ ██╔══╝  ██║     ██║   ██║
#        ██║     ███████╗╚██████╗╚██████╔╝
#        ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝
# -----------------------------------------------------------------------------
#  PECU Release Selector · 2025-06-19
#  Author  : Daniel Puente García — https://github.com/Danilop95
#  Donate  : https://buymeacoffee.com/danilop95
#  Project : Proxmox Enhanced Configuration Utility (PECU)
# -----------------------------------------------------------------------------

set -Eeuo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]] && tput setaf 1 &>/dev/null; then
  NC=$(tput sgr0); B=$(tput bold); U=$(tput smul); SO=$(tput smso); RS=$(tput rmso)
  R=$(tput setaf 1); G=$(tput setaf 2); Y=$(tput setaf 3)
  O=$(tput setaf 208); L=$(tput setaf 4); M=$(tput setaf 5); C=$(tput setaf 6)
else NC='' B='' U='' SO='' RS='' R='' G='' Y='' O='' L='' M='' C=''; fi

declare -A COL=( [stable]=$G [beta]=$M [preview]=$C
                 [experimental]=$O [nightly]=$L [legacy]=$Y [other]=$NC )

# ── constants ────────────────────────────────────────────────────────────────
REPO="Danilop95/Proxmox-Enhanced-Configuration-Utility"
API="https://api.github.com/repos/$REPO/releases?per_page=100"
RAW="https://raw.githubusercontent.com/$REPO"
SITE="https://pecu.tools"
RELEASES_URL="$SITE/releases"
PREMIUM_URL="$SITE/premium"

# ── utils (alignment-safe) ───────────────────────────────────────────────────
cols() { tput cols 2>/dev/null || echo 80; }
repeat() { # repeat <char> <count>
  local ch="$1" n="${2:-0}"
  printf '%*s' "$n" '' | tr ' ' "${ch:0:1}"
}
strip_ansi() { sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'; }
vislen() { # visible length (UTF-8; ignore ANSI)
  local s="$1"
  local n
  n=$(printf '%s' "$s" | strip_ansi | wc -m)
  printf '%s' "${n//[[:space:]]/}"
}
pad_line() { # pad_line <width> "<text>"
  local w="$1" text="$2" n pad
  n=$(vislen "$text")
  (( n > w )) && { printf '%s' "$text"; return; }
  pad=$((w - n))
  printf '%s%*s' "$text" "$pad" ''
}

box_single() { # box_single <total_width> [lines...]
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

box_double() { # box_double <total_width> <title> [lines...]
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

# Robust temp workspace (avoid mktemp failures under /tmp issues)
init_workspace() {
  local base="${TMPDIR:-/tmp}"
  [[ -d $base && -w $base ]] || base="/var/tmp"
  [[ -d $base && -w $base ]] || base="$HOME/.pecu_tmp"
  mkdir -p "$base"
  WORKDIR="$base/pecu.$$.$RANDOM"
  mkdir -p "$WORKDIR"
  trap 'rm -rf -- "$WORKDIR"' EXIT
}
init_workspace

# ── banner ───────────────────────────────────────────────────────────────────
banner() {
  clear
  printf "${L}${B}PROXMOX ENHANCED CONFIG UTILITY (PECU)${NC}\n${Y}"
cat <<'ASCII'
 ██████╗ ███████╗ ██████╗██╗   ██╗
 ██╔══██╗██╔════╝██╔════╝██║   ██║
 ██████╔╝█████╗  ██║     ██║   ██║
 ██╔═══╝ ██╔══╝  ██║     ██║   ██║
 ██║     ███████╗╚██████╗╚██████╔╝
 ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝
ASCII
  printf "${C}Daniel Puente García  •  BuyMeACoffee: https://buymeacoffee.com/danilop95${NC}\n"
  printf "${C}Website: ${U}%s${NC}\n\n" "$SITE"
}

# ── premium & web notices ────────────────────────────────────────────────────
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
      mkdir -p "$lp"
      printf '%s\n' "$key" > "$lp/license"
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

# ── environment & deps ───────────────────────────────────────────────────────
proxmox_hint() {
  if [[ -f /etc/pve/.version ]]; then
    echo -e "${L}Proxmox VE detected${NC}\n"
  fi
}

fix_proxmox_repos() {
  if [[ -f /etc/pve/.version ]] && [[ ! -f /etc/apt/sources.list.d/pve-no-subscription.list ]]; then
    echo -e "${Y}Configuring community repositories for Proxmox (no subscription)…${NC}"
    [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]] && sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
    [[ -f /etc/apt/sources.list.d/ceph.list ]] && sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list 2>/dev/null || true
    printf "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription\n" > /etc/apt/sources.list.d/pve-no-subscription.list
    printf "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription\n" > /etc/apt/sources.list.d/ceph-no-subscription.list
    apt-get -qq update || true
  fi
}

banner
proxmox_hint
show_web_info

for pkg in curl jq tar find awk sed; do
  if ! command -v "$pkg" &>/dev/null; then
    echo -e "${Y}Installing dependency: $pkg …${NC}"
    [[ -f /etc/pve/.version ]] && fix_proxmox_repos
    sudo DEBIAN_FRONTEND=noninteractive apt-get -qq update || true
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install "$pkg" || {
      if [[ "$pkg" == "jq" ]]; then
        echo -e "${Y}Trying direct jq binary…${NC}"
        curl -fsSL "https://github.com/jqlang/jq/releases/latest/download/jq-linux64" -o "$WORKDIR/jq" \
          && chmod +x "$WORKDIR/jq" && sudo mv "$WORKDIR/jq" /usr/local/bin/jq \
          || { echo -e "${R}Failed to install jq.${NC}"; exit 1; }
      else
        echo -e "${R}Failed to install $pkg.${NC}"; exit 1
      fi
    }
  fi
done

security_notice

# ── fetch releases (skip Deprecated/Obsolete/Retired) ────────────────────────
echo -e "${Y}Fetching available releases…${NC}"
mapfile -t META < <(
  curl -fsSL "$API" | jq -r '
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

# ── table layout (clean alignment) ───────────────────────────────────────────
TW=$(cols)
ID_W=3; TAG_W=14; DATE_W=10
MAX_CH=$(printf '%s\n' "${META[@]}" | cut -d'|' -f2 | awk '{print length}' | sort -nr | head -1)
(( MAX_CH<7 )) && MAX_CH=7
CH_W=$((MAX_CH+2))
TITLE_W=$((TW - ID_W - TAG_W - DATE_W - CH_W - 6))
((TITLE_W>42)) && TITLE_W=42
((TITLE_W<18)) && TITLE_W=18

echo -e "\n${B}Available Releases:${NC}"
printf "${B}%-${ID_W}s %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]${NC}\n" "#" "TAG" "TITLE" "DATE" "CHANNEL"
printf '%s\n' "$(repeat '─' "$TW")"

declare -A IDX; n=1
for rec in "${META[@]}"; do
  IFS='|' read -r d ch tag ttl asset <<<"$rec"
  lc=${ch,,}; [[ $lc =~ ^(stable|beta|preview|experimental|nightly|legacy)$ ]] || lc=other
  cut=$ttl; (( ${#cut}>TITLE_W )) && cut="${cut:0:$((TITLE_W-2))}…"
  latest=''; [[ $rec == "$LATEST" ]] && latest=' ★LATEST'
  printf "${COL[$lc]} %-${ID_W}d %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]${NC}%s\n" \
         "$n" "$tag" "$cut" "$d" "$lc" "$latest"
  IDX[$n]="$tag|$lc|$asset"
  ((n++))
done

show_premium_teaser
printf " %-${ID_W}s Exit\n" 0

# ── selection ────────────────────────────────────────────────────────────────
while :; do
  read -rp $'\nSelect release # (or P for Premium): ' sel
  if [[ "$sel" =~ ^[Pp]$ ]]; then
    premium_info_menu
    banner; proxmox_hint; show_web_info
    echo -e "\n${B}Available Releases:${NC}"
    printf "${B}%-${ID_W}s %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]${NC}\n" "#" "TAG" "TITLE" "DATE" "CHANNEL"
    printf '%s\n' "$(repeat '─' "$TW")"
    n=1; for rec in "${META[@]}"; do
      IFS='|' read -r d ch tag ttl asset <<<"$rec"
      lc=${ch,,}; [[ $lc =~ ^(stable|beta|preview|experimental|nightly|legacy)$ ]] || lc=other
      cut=$ttl; (( ${#cut}>TITLE_W )) && cut="${cut:0:$((TITLE_W-2))}…"
      latest=''; [[ $rec == "$LATEST" ]] && latest=' ★LATEST'
      printf "${COL[$lc]} %-${ID_W}d %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]${NC}%s\n" \
             "$n" "$tag" "$cut" "$d" "$lc" "$latest"
      ((n++))
    done
    show_premium_teaser
    printf " %-${ID_W}s Exit\n" 0
    continue
  fi
  if [[ "$sel" =~ ^[0-9]+$ ]]; then
    (( sel==0 )) && exit 0
    [[ ${IDX[$sel]-} ]] && break || echo -e "${R}Invalid ID.${NC}"
  else
    echo -e "${Y}Enter a number (1-${#META[@]}), 'P' for Premium, or '0' to exit.${NC}"
  fi
done
IFS='|' read -r TAG CHN ASSET <<<"${IDX[$sel]}"

# ── optional UI deps ─────────────────────────────────────────────────────────
ui_missing=()
for d in whiptail dialog; do command -v "$d" &>/dev/null || ui_missing+=("$d"); done
if ((${#ui_missing[@]})); then
  echo -e "${Y}Missing optional UI packages: ${ui_missing[*]}${NC}"
  read -rp "Install them automatically? [Y/n]: " ans
  [[ $ans =~ ^[Nn]$ ]] || for d in "${ui_missing[@]}"; do
      echo -e "${Y}Installing $d …${NC}"
      sudo DEBIAN_FRONTEND=noninteractive apt-get -y install "$d" || true
    done
fi

# ── confirmation (boxed, aligned) ────────────────────────────────────────────
show_selected_release_box() {
  local W="$1"
  ((W>72)) && W=72
  box_single "$W" \
    "${B}SELECTED RELEASE${NC}" \
    "Tag:     ${TAG}" \
    "Channel: ${CHN^}" \
    "Source:  GitHub"
}
banner
show_selected_release_box "$(cols)"
read -rp "Press Y to run | any other key to cancel: " ok
[[ $ok =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

# ── execution helpers (robust workspace, no mktemp) ──────────────────────────
run_raw() {
  local rel="$1"; [[ -n "${rel:-}" ]] || return 1
  local url="$RAW/$TAG/$rel"
  if curl -sfIL "$url" &>/dev/null; then
    local runner="$WORKDIR/runner.sh"
    if curl -fsSL "$url" -o "$runner"; then
      chmod +x "$runner"; "$runner"; return 0
    fi
  fi
  return 1
}

run_asset() {
  [[ -n "${ASSET:-}" ]] || return 1
  local tgz="$WORKDIR/pecu.tgz"
  curl -fsSL "$ASSET" -o "$tgz" || return 1
  tar -xzf "$tgz" -C "$WORKDIR"
  local sh; sh=$(find "$WORKDIR" -name proxmox-configurator.sh -type f | head -n1 || true)
  [[ -f "${sh:-}" ]] || return 1
  chmod +x "$sh"; "$sh"
}

# ── launch ───────────────────────────────────────────────────────────────────
echo -e "${G}→ Executing $TAG …${NC}"
START=$(date +%s)
run_raw "src/proxmox-configurator.sh"  || true
run_raw "proxmox-configurator.sh"      || true

if (( $(date +%s) - START < 3 )); then
  echo -e "${Y}Script ended quickly — trying packaged asset…${NC}"
  run_asset || { echo -e "${R}Error:${NC} No runnable content found."; exit 1; }
fi
