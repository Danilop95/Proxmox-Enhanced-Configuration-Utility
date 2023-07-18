#!/bin/bash

# Colors
RED='\e[0;31m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
YELLOW='\e[0;33m'
NC='\e[0m' # No Color

# Backup directory
BACKUP_DIRECTORY="$(dirname "$0")/backup-script"

# Check if the user is root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root.${NC}"
    exit 1
fi

# Check if sudo is installed, if not, install it.
if ! command -v sudo &> /dev/null; then
    echo -e "${BLUE}sudo is not installed. Installing...${NC}"
    apt-get update
    apt-get install sudo -y
fi

# Function to ask if the user wants to continue
ask_to_continue() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| The following step will:                       |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}-------------------------------------------------${NC}"
    echo -n -e "${BLUE}Do you want to continue?${NC} (y/n): "
    read response
    case $response in
        [yY])
            echo -e "${BLUE}Continuing...${NC}"
            ;;
        *)
            echo -e "${RED}Skipping to the next step.${NC}"
            return 1
            ;;
    esac
}

# Function to create a backup of the file
create_backup() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Creating a backup of sources.list              |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # Check if the backup directory exists
    if [[ ! -d "$BACKUP_DIRECTORY" ]]; then
        mkdir -p "$BACKUP_DIRECTORY"
        echo -e "${GREEN}Backup directory created at $BACKUP_DIRECTORY.${NC}"
    fi

    # Limit the maximum number of backups to 5
    backup_files=("${BACKUP_DIRECTORY}/sources.list.bak_"*)
    if [[ ${#backup_files[@]} -ge 5 ]]; then
        echo -e "${BLUE}Maximum number of backups reached. Delete some backups to create new ones.${NC}"
        return 1
    fi

    backup_file="${BACKUP_DIRECTORY}/sources.list.bak_$(date +%Y%m%d_%H%M%S)"
    sudo cp "/etc/apt/sources.list" "$backup_file"
    echo -e "${GREEN}Backup created at $backup_file.${NC}"
}

# Function to restore a previous backup of the file
restore_backup() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Restoring a previous backup                    |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    backup_files=("${BACKUP_DIRECTORY}/sources.list.bak_"*)

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo -e "${RED}No backups available.${NC}"
        return 1
    fi

    echo -e "${BLUE}Select a backup to restore:${NC}"
    for ((i=0; i<${#backup_files[@]}; i++)); do
        echo -e "${BLUE} $((i+1)))${NC} ${backup_files[$i]}"
    done

    read -p "$(echo -e ${BLUE}Enter the backup number:${NC} )" backup_number

    # Check if the backup number is valid
    if ! [[ "$backup_number" =~ ^[1-5]$ ]]; then
        echo -e "${RED}Invalid option.${NC}"
        return 1
    fi

    backup_file="${backup_files[$((backup_number-1))]}"
    if [[ -f "$backup_file" ]]; then
        echo -e "${BLUE}Preview of the backup file:${NC}"
        echo "-----------------------------------------"
        cat "$backup_file"
        echo "-----------------------------------------"
        echo -n -e "${BLUE}Do you want to restore this backup?${NC} (y/n): "
        read response
        case $response in
            [yY])
                sudo cp "$backup_file" "/etc/apt/sources.list"
                echo -e "${GREEN}Backup restored successfully.${NC}"
                ;;
            *)
                echo -e "${RED}Operation canceled.${NC}"
                ;;
        esac
    else
        echo -e "${RED}Backup file not found.${NC}"
        return 1
    fi
}

# Function to edit the sources.list file
edit_sources_list() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}|          Editing sources.list file             |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${YELLOW}The sources.list file will be opened in the text editor. Make the necessary changes.${NC}"
    echo -e "${YELLOW}When you are done, save the changes and close the text editor to continue.${NC}"
    echo -e "${YELLOW}Press Enter to continue.${NC}"
    read

    sudo $EDITOR /etc/apt/sources.list
    echo -e "${GREEN}sources.list file edited successfully.${NC}"
}

# Main function to execute the configuration steps
execute_configuration() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}|          Proxmox VE Configuration             |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    ask_to_continue "Create a backup of sources.list"
    if [[ $? -eq 0 ]]; then
        create_backup
    fi

    ask_to_continue "Restore a previous backup of sources.list"
    if [[ $? -eq 0 ]]; then
        restore_backup
    fi

    ask_to_continue "Edit the sources.list file"
    if [[ $? -eq 0 ]]; then
        edit_sources_list
    fi

    echo -e "${GREEN}Configuration completed.${NC}"
}

# Execute the main function
execute_configuration
