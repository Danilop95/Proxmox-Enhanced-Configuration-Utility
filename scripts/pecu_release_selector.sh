#!/bin/bash
# -----------------------------------------------------------------------------
#        ██████╗ ███████╗ ██████╗██╗   ██╗
#        ██╔══██╗██╔════╝██╔════╝██║   ██║
#        ██████╔╝█████╗  ██║     ██║   ██║
#        ██╔═══╝ ██╔══╝  ██║     ██║   ██║
#        ██║     ███████╗╚██████╗╚██████╔╝
#        ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝ 
# -----------------------------------------------------------------------------
# PECU Release Selector - By Daniel Puente García (Danielop95/DVNILXP)
# Version: 1.0 - 14/04/2025
# -----------------------------------------------------------------------------

# Color definitions
RED='\e[0;31m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
YELLOW='\e[0;33m'
NC='\e[0m'  # No color

# GitHub repository information
GITHUB_REPO="Danilop95/Proxmox-Enhanced-Configuration-Utility"
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases"

# -----------------------------------------------------------------------------
# Function: Check network connectivity
# -----------------------------------------------------------------------------
check_network() {
    echo -ne "${YELLOW}Checking network connectivity...${NC} "
    if ping -c 1 -W 2 google.com &> /dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo -e "${RED}Network connectivity appears to be unavailable or DNS resolution is failing."
        echo -e "Please check your network and DNS settings before running this script.${NC}"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Function: Check and install dependencies interactively
# -----------------------------------------------------------------------------
check_dependencies() {
    check_network

    local deps=(curl jq)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo -e "${RED}Dependency '$dep' is not installed.${NC}"
            read -rp "Would you like to install '$dep'? (y/N): " answer
            case "$answer" in
                [yY]|[yY][eE][sS])
                    echo -e "${YELLOW}Updating package lists...${NC}"
                    if ! apt-get update; then
                        echo -e "${RED}Failed to update package lists. This may be due to a temporary "
                        echo -e "failure in DNS resolution or network issues. Please try running:"
                        echo -e "    apt-get update --fix-missing"
                        echo -e "or check your network settings before continuing.${NC}"
                        exit 1
                    fi
                    echo -e "${YELLOW}Installing $dep...${NC}"
                    if ! apt-get install -y "$dep"; then
                        echo -e "${RED}Error: Failed to install $dep. Exiting.${NC}"
                        exit 1
                    fi
                    ;;
                *)
                    echo -e "${RED}Cannot proceed without $dep. Exiting.${NC}"
                    exit 1
                    ;;
            esac
        else
            echo -e "${GREEN}Dependency '$dep' is already installed.${NC}"
        fi
    done
}

# -----------------------------------------------------------------------------
# Loading Screen (Banner and Spinner)
# -----------------------------------------------------------------------------
show_loading_banner() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}  PROXMOX ENHANCED CONFIG UTILITY (PECU)        ${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}      By Daniel Puente García (Danielop95/DVNILXP)${NC}"
    echo

    local banner_lines=(
    '         ██████╗ ███████╗ ██████╗██╗   ██╗'
    '         ██╔══██╗██╔════╝██╔════╝██║   ██║'
    '         ██████╔╝█████╗  ██║     ██║   ██║'
    '         ██╔═══╝ ██╔══╝  ██║     ██║   ██║'
    '         ██║     ███████╗╚██████╗╚██████╔╝'
    '         ╚═╝     ╚══════╝ ╚═════╝ ╚═════╝'
    )

    echo -e "${YELLOW}"
    for line in "${banner_lines[@]}"; do
        echo "$line"
        sleep 0.07
    done
    echo -e "${NC}"
    sleep 0.5
}

show_release_spinner() {
    local messages=(
        "Fetching Stable Releases..."
        "Fetching Pre-release Versions..."
        "Preparing Version Selector..."
        "Recommended: Use Stable Release!"
        "Proxmox Enhanced Utility"
    )

    echo -ne "${YELLOW}Initializing Release Selector: ${NC}"
    for msg in "${messages[@]}"; do
        printf "\r${YELLOW}%-50s${NC}" "$msg"
        sleep 0.7
    done
    echo
    sleep 1
}

print_banner() {
    clear
    cat << 'EOF'
===========================================
   Proxmox Enhanced Configuration Utility
           Version Selector
===========================================
EOF
}

# -----------------------------------------------------------------------------
# Fetch releases from GitHub API
# -----------------------------------------------------------------------------
fetch_releases() {
    local json
    echo -e "${BLUE}Fetching release information from GitHub...${NC}"
    json=$(curl -sL "$API_URL")
    if [[ -z "$json" ]]; then
        echo -e "${RED}Error: Failed to fetch release information from GitHub.${NC}"
        exit 1
    fi

    # Format: tag_name | prerelease | published_at
    echo "$json" | jq -r '.[] | "\(.tag_name) | \(.prerelease) | \(.published_at)"'
}

# -----------------------------------------------------------------------------
# Display the release selection menu with color differentiation
# -----------------------------------------------------------------------------
display_menu() {
    local releases=("$@")
    local recommended_index=-1

    # First pass: determine the recommended (first stable release) index
    for i in "${!releases[@]}"; do
        local pre
        pre=$(echo "${releases[$i]}" | cut -d'|' -f2 | xargs)
        if [[ "$pre" == "false" ]] && [[ $recommended_index -eq -1 ]]; then
            recommended_index=$i
            break
        fi
    done

    echo -e "\nSelect a PECU version to execute:"
    echo "-----------------------------------"
    local index=1
    for rel in "${releases[@]}"; do
        local tag pre published
        tag=$(echo "$rel" | cut -d'|' -f1 | xargs)
        pre=$(echo "$rel" | cut -d'|' -f2 | xargs)
        published=$(echo "$rel" | cut -d'|' -f3 | xargs)

        if [[ "$pre" == "true" ]]; then
            # Pre-release: show in yellow
            echo -e "  ${index}) ${YELLOW}${tag} (Pre-release)${NC} - Published: ${published}"
        else
            # Stable release: show in green; mark as RECOMMENDED if first stable
            if [[ $((index-1)) -eq $recommended_index ]]; then
                echo -e "  ${index}) ${GREEN}${tag} (Stable) [RECOMMENDED]${NC} - Published: ${published}"
            else
                echo -e "  ${index}) ${GREEN}${tag} (Stable)${NC} - Published: ${published}"
            fi
        fi
        ((index++))
    done
    echo "  0) Exit"
    echo "-----------------------------------"
}

# -----------------------------------------------------------------------------
# Prompt the user to select a release and return its tag
# -----------------------------------------------------------------------------
select_release() {
    local releases=("$@")
    local choice
    read -rp "Enter the option number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if [ "$choice" -eq 0 ]; then
            echo -e "${YELLOW}Exiting.${NC}"
            exit 0
        elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#releases[@]}" ]; then
            local selected
            selected="${releases[$((choice-1))]}"
            local tag
            tag=$(echo "$selected" | cut -d'|' -f1 | xargs)
            echo "$tag"
        else
            echo -e "${RED}Invalid selection. Please try again.${NC}" >&2
            select_release "${releases[@]}"
        fi
    else
        echo -e "${RED}Invalid input. Please enter a number.${NC}" >&2
        select_release "${releases[@]}"
    fi
}

# -----------------------------------------------------------------------------
# Execute the selected version of the PECU script
# -----------------------------------------------------------------------------
execute_release() {
    local tag="$1"
    echo -e "\nSelected version: ${BLUE}${tag}${NC}"
    echo -e "${YELLOW}Fetching and executing PECU from GitHub...${NC}"
    # Download and execute the script directly from GitHub using the selected tag.
    bash <(curl -sL "https://raw.githubusercontent.com/${GITHUB_REPO}/${tag}/proxmox-configurator.sh")
}

# -----------------------------------------------------------------------------
# Main Execution Flow
# -----------------------------------------------------------------------------
main() {
    # Check and, if necessary, install required dependencies.
    check_dependencies

    show_loading_banner
    show_release_spinner
    print_banner

    # Fetch release information.
    mapfile -t releases_array < <(fetch_releases)
    if [ "${#releases_array[@]}" -eq 0 ]; then
        echo -e "${RED}No releases found for repository ${GITHUB_REPO}.${NC}"
        exit 1
    fi

    display_menu "${releases_array[@]}"

    selected_tag=$(select_release "${releases_array[@]}")
    read -rp "Proceed to execute version ${selected_tag}? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy] ]]; then
        execute_release "$selected_tag"
    else
        echo -e "${YELLOW}Operation cancelled.${NC}"
        exit 0
    fi
}

# Execute the script
main
