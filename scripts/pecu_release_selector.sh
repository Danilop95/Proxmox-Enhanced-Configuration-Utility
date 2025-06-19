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
# -----------------------------------------------------------------------------

set -Eeuo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]] && tput setaf 1 &>/dev/null; then
  NC=$(tput sgr0); B=$(tput bold)
  R=$(tput setaf 1); G=$(tput setaf 2); Y=$(tput setaf 3)
  O=$(tput setaf 208); L=$(tput setaf 4); M=$(tput setaf 5); C=$(tput setaf 6)
else NC='' B='' R='' G='' Y='' O='' L='' M='' C=''; fi

declare -A COL=(
  [stable]=$G [beta]=$M [preview]=$C
  [experimental]=$O [nightly]=$L [legacy]=$Y [other]=$NC )

# ── constants ────────────────────────────────────────────────────────────────
REPO="Danilop95/Proxmox-Enhanced-Configuration-Utility"
API="https://api.github.com/repos/$REPO/releases?per_page=100"
RAW="https://raw.githubusercontent.com/$REPO"

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
  printf "${C}Daniel Puente García  •  BuyMeACoffee: https://buymeacoffee.com/danilop95${NC}\n\n"
}
banner

# ── base dependencies ────────────────────────────────────────────────────────
for pkg in curl jq tar find; do
  command -v "$pkg" &>/dev/null && continue
  echo -e "${Y}Installing dependency: $pkg …${NC}"
  sudo DEBIAN_FRONTEND=noninteractive apt-get -qq update
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y install "$pkg"
done

# ── fetch releases (skip Deprecated) ─────────────────────────────────────────
mapfile -t META < <(
  curl -fsSL "$API" | jq -r '
    .[]
    | select(.body|test("PECU-Channel:"))
    | select(.body|test("Deprecated|Obsolete|Retired";"i")|not)
    | .asset = ((.assets[]? | select(.name|test("\\.tar\\.gz$")) | .browser_download_url) // "")
    | { tag:.tag_name,
        date:(.published_at|split("T")[0]),
        chan:(.body|capture("PECU-Channel:\\s*(?<x>[^\r\n]+)") .x),
        title:(.body|capture("PECU-Title:\\s*(?<x>[^\r\n]+)") .x),
        asset:.asset }
    | "\(.date)|\(.chan)|\(.tag)|\(.title)|\(.asset)"')

((${#META[@]})) || { echo -e "${R}No releases found.${NC}"; exit 1; }
IFS=$'\n' META=($(sort -r <<<"${META[*]}"))
LATEST=$(printf '%s\n' "${META[@]}" | grep -m1 '|[Ss]table|' || true)

# ── table layout ─────────────────────────────────────────────────────────────
TW=$(tput cols 2>/dev/null || echo 80)
ID_W=3 TAG_W=14 DATE_W=10
MAX_CH=$(printf '%s\n' "${META[@]}" | cut -d'|' -f2 | awk '{print length}' | sort -nr | head -1)
CH_W=$((MAX_CH+2))
TITLE_W=$((TW - ID_W - TAG_W - DATE_W - CH_W - 3))
((TITLE_W>34)) && TITLE_W=34
((TITLE_W<16)) && TITLE_W=16

printf "${B}%-${ID_W}s %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]${NC}\n" \
       "#" "TAG" "TITLE" "DATE" "CHANNEL"
printf '%*s\n' "$TW" '' | tr ' ' '─'

declare -A IDX; n=1
for rec in "${META[@]}"; do
  IFS='|' read -r d ch tag ttl asset <<<"$rec"
  lc=${ch,,}; [[ $lc =~ ^(stable|beta|preview|experimental|nightly|legacy)$ ]] || lc=other
  cut=$ttl; (( ${#cut}>TITLE_W )) && cut="${cut:0:$((TITLE_W-2))}…"
  star=''; [[ $rec == "$LATEST" ]] && star=' ★LATEST'
  printf "${COL[$lc]} %-${ID_W}d %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]%s${NC}\n" \
         "$n" "$tag" "$cut" "$d" "$lc" "$star"
  IDX[$n]="$tag|$lc|$asset"
  ((n++))
done
printf "\n %-${ID_W}s Exit\n" 0

# ── selection ────────────────────────────────────────────────────────────────
while :; do
  read -rp $'\nSelect release #: ' id
  [[ $id =~ ^[0-9]+$ ]] || { echo "Digits only."; continue; }
  (( id==0 )) && exit 0
  [[ ${IDX[$id]-} ]] && break || echo "Invalid ID."
done
IFS='|' read -r TAG CHN ASSET <<<"${IDX[$id]}"

# ── optional UI deps ─────────────────────────────────────────────────────────
ui_missing=()
for d in whiptail dialog; do command -v "$d" &>/dev/null || ui_missing+=("$d"); done
if ((${#ui_missing[@]})); then
  echo -e "${Y}Missing optional UI packages: ${ui_missing[*]}${NC}"
  read -rp "Install them automatically? [Y/n]: " ans
  [[ $ans =~ ^[Nn] ]] || for d in "${ui_missing[@]}"; do
      echo -e "${Y}Installing $d …${NC}"
      sudo DEBIAN_FRONTEND=noninteractive apt-get -y install "$d"
    done
fi

# ── confirmation ─────────────────────────────────────────────────────────────
note=${CHN^}; [[ $CHN == experimental ]] && note="High-risk build"
bar=$(printf '%*s' "$TW" '' | tr ' ' '─')
banner
echo -e "${COL[$CHN]}${bar}\nTAG: $TAG\nNOTE: $note\n${bar}${NC}"
read -rp "Press Y to run | any other key to cancel: " ok
[[ $ok =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

# ── execution helpers ────────────────────────────────────────────────────────
run_raw() {
  local rel="$1"
  [[ -z $rel ]] && return 1
  local url="$RAW/$TAG/$rel"
  curl -sfIL "$url" &>/dev/null || return 1
  local tmp; tmp=$(mktemp --suffix .sh) || return 1
  curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp"; return 1; }
  chmod +x "$tmp"; "$tmp"
}

run_asset() {
  [[ -z $ASSET ]] && return 1
  local tmp; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "$ASSET" -o "$tmp/pecu.tgz" || return 1
  tar -xzf "$tmp/pecu.tgz" -C "$tmp"
  local sh; sh=$(find "$tmp" -name proxmox-configurator.sh -type f | head -n1)
  [[ -f $sh ]] || return 1
  chmod +x "$sh"; "$sh"
}

# ── launch ───────────────────────────────────────────────────────────────────
echo -e "${G}→ Executing $TAG …${NC}"
START=$(date +%s)
run_raw "src/proxmox-configurator.sh"  || true
run_raw "proxmox-configurator.sh"      || true

(( $(date +%s) - START < 3 )) && {
  echo -e "${Y}Script ended quickly — trying packaged asset…${NC}"
  run_asset || { echo -e "${R}Error:${NC} No runnable content found."; exit 1; }
}
