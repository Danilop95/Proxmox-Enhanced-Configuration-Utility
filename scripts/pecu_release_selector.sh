#!/usr/bin/env bash
# -----------------------------------------------------------------------------
#        ██████╗ ███████╗ ██████╗██╗   ██╗
#        ██╔══██╗██╔════╝██╔════╝██║   ██║
#        ██████╔╝█████╗  ██║     ██║   ██║
#        ██╔═══╝ ██╔══╝  ██║     ██║   ██║
#        ██║     ███████╗╚██████╗╚██████╔╝
#        ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝ 
# -----------------------------------------------------------------------------
#  PECU ASCII-only Release Selector · 2025-06-17
#  Author  : Daniel Puente García — https://github.com/Danilop95
# -----------------------------------------------------------------------------

set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]] && tput setaf 1 &>/dev/null; then
  NC=$(tput sgr0); B=$(tput bold)
  R=$(tput setaf 1); G=$(tput setaf 2); Y=$(tput setaf 3)
  O=$(tput setaf 208); L=$(tput setaf 4); M=$(tput setaf 5); C=$(tput setaf 6)
else NC=''; B=''; R=''; G=''; Y=''; O=''; L=''; M=''; C=''; fi

# Named colours for banner convenience
BLUE=$L; GREEN=$G; YELLOW=$Y

declare -A COL=([stable]=$G       [beta]=$M      [preview]=$C \
                [experimental]=$O [nightly]=$L   [legacy]=$Y \
                [other]=$NC)
declare -A ICO=([stable]="✔"   [beta]="β"   [preview]="℗" \
                [experimental]="⚠" [nightly]="☾" [legacy]="✝" \
                [other]="?" )

REPO="Danilop95/Proxmox-Enhanced-Configuration-Utility"
API="https://api.github.com/repos/$REPO/releases"
RAW="https://raw.githubusercontent.com/$REPO"

AUTHOR="Daniel Puente García — https://github.com/Danilop95"
BMAC_URL="https://www.buymeacoffee.com/danilop95"

# ── banner animation ─────────────────────────────────────────────────────────
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

show_loading_banner

# ── dependencies ─────────────────────────────────────────────────────────────
need(){ command -v "$1" &>/dev/null || { echo -e "${Y}Missing '$1'…${NC}"; sudo apt-get update -qq && sudo apt-get install -y "$1"; }; }
for b in curl jq tar find; do need "$b"; done

# ── fetch metadata (date|channel|tag|title|desc|assetURL) ────────────────────
mapfile -t META < <(
  curl -fsSL "$API" | jq -r '
    .[]
    | select(.body|test("PECU-Channel:"))
    | .asset = (
        (.assets[]? | select(.name|test("\\.tar\\.gz$")) | .browser_download_url) // ""
      )
    | select(.body|test("Deprecated|Obsolete|Retired";"i")|not)
    | {
        tag:.tag_name,
        date:(.published_at|split("T")[0]),
        chan:(.body|capture("PECU-Channel:\\s*(?<x>[^\r\n]+)") .x),
        title:(.body|capture("PECU-Title:\\s*(?<x>[^\r\n]+)") .x),
        desc:(.body|capture("PECU-Desc:\\s*(?<x>[^\r\n]+)") .x),
        asset:.asset
      }
    | "\(.date)|\(.chan)|\(.tag)|\(.title)|\(.desc)|\(.asset)"' )

(( ${#META[@]} )) || { echo -e "${R}No valid releases found.${NC}"; exit 1; }
IFS=$'\n' META=($(sort -r <<<"${META[*]}"))

LATEST=$(printf '%s\n' "${META[@]}" | grep -m1 '|[Ss]table|' || true)

# ── table widths ─────────────────────────────────────────────────────────────
TW=$(tput cols 2>/dev/null || echo 80)
ID_W=3 TAG_W=14 DATE_W=10
MAX_CH=$(printf '%s\n' "${META[@]}" | cut -d'|' -f2 | awk '{print length}' | sort -nr | head -1)
CH_W=$(( MAX_CH + 2 ))
TITLE_W=$(( TW - ID_W - TAG_W - DATE_W - CH_W - 4 ))
(( TITLE_W>30 )) && TITLE_W=30
(( TITLE_W<12 )) && TITLE_W=12

# ── screen & legend ──────────────────────────────────────────────────────────
clear
echo -e "${B}PECU Channel Legend${NC}"
printf "  ${G}Stable${NC}        Production ready\n"
printf "  ${M}Beta${NC}          Release candidate\n"
printf "  ${C}Preview${NC}       Feature preview\n"
printf "  ${O}Experimental${NC}  High-risk build\n"
printf "  ${L}Nightly${NC}       Un-tested daily build\n"
printf "  ${Y}Legacy${NC}        Older long-term build\n\n"

printf "${B}%-${ID_W}s %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]${NC}\n" \
       "#" "TAG" "TITLE" "DATE" "CHANNEL"
printf '%*s\n' "$TW" '' | tr ' ' '─'

# ── list ─────────────────────────────────────────────────────────────────────
declare -A IDX; n=1
for rec in "${META[@]}"; do
  IFS='|' read -r d ch tag ttl desc asset <<<"$rec"
  lc=${ch,,}; [[ $lc =~ ^(stable|beta|preview|experimental|nightly|legacy)$ ]] || lc=other
  cut=$ttl; (( ${#cut}>TITLE_W )) && cut="${cut:0:$((TITLE_W-2))}…"
  flag=''; [[ $rec == "$LATEST" ]] && flag=' ★LATEST'
  printf "${COL[$lc]} %-${ID_W}d %-${TAG_W}s %-${TITLE_W}s %-${DATE_W}s [%-${MAX_CH}s]%s${NC}\n" \
         "$n" "$tag" "$cut" "$d" "$lc" "$flag"
  IDX[$n]="$tag|$ttl|$desc|$lc|$asset"
  ((n++))
done
printf "\n %-${ID_W}d Exit\n" 0

# ── selection ────────────────────────────────────────────────────────────────
while :; do
  read -rp $'\nSelect #release: ' id
  [[ $id =~ ^[0-9]+$ ]] || { echo "Digits only."; continue; }
  (( id==0 )) && exit 0
  [[ ${IDX[$id]-} ]] && break || echo "Invalid ID."
done
IFS='|' read -r TAG TTL DSC CHN ASSET <<<"${IDX[$id]}"

# ── confirmation banner ─────────────────────────────────────────────────────
case $CHN in
  stable)        clr=$G; note="Safe for production";;
  beta|preview)  clr=$Y; note="May contain bugs";;
  experimental)  clr=$O; note="⚠ High-risk build";;
  nightly)       clr=$L; note="Un-tested nightly";;
  legacy)        clr=$Y; note="Legacy (older stable)";;
  *)             clr=$C; note="Uncategorised";;
esac
bar=$(printf '%*s' "$TW" '' | tr ' ' '─')
clear; echo -e "${clr}${bar}\nTAG: $TAG\nTITLE: $TTL\nNOTE: $note\n${bar}${NC}"
read -rp "Press Y to run | any other key to cancel: " ok
[[ $ok =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

# ── execution helpers ───────────────────────────────────────────────────────
run_raw(){ path="$1"; url="$RAW/$TAG/$path"
  curl -sfI "$url" &>/dev/null && exec bash <(curl -fsSL "$url"); }

run_asset(){ [[ -z $ASSET ]] && return
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "$ASSET" -o "$tmp/pecu.tgz" || return
  tar -xzf "$tmp/pecu.tgz" -C "$tmp"
  sh=$(find "$tmp" -name proxmox-configurator.sh -type f | head -n1)
  [[ -f $sh ]] && chmod +x "$sh" && exec "$sh"; }

echo -e "${G}→ Executing $TAG …${NC}"
run_raw "src/proxmox-configurator.sh"
run_raw "proxmox-configurator.sh"
run_asset

echo -e "${R}Error:${NC} No runnable script found for $TAG."
exit 1
