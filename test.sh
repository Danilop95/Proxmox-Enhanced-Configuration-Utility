#!/bin/bash

# Colors
ROJO='\e[0;31m'
VERDE='\e[0;32m'
AZUL='\e[0;34m'
NC='\e[0m' # No Color

# Function to display language selection menu
menu_idioma() {
    clear
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}|      Seleccione el Idioma/Select Language      |${NC}"
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${VERDE} 1) Español${NC}"
    echo -e "${VERDE} 2) English${NC}"
    echo -e "${AZUL}=================================================${NC}"
    read -p "$(echo -e ${AZUL}Seleccione una opción:${NC} )" opcion

    case $opcion in
        1)
            echo -e "${AZUL}Seleccionado: Español${NC}"
            sleep 2
            ejecutar_script <(curl -s https://raw.githubusercontent.com/Danilop95/Proxmox-local/main/es.sh)
            ;;
        2)
            echo -e "${AZUL}Selected: English${NC}"
            sleep 2
            ejecutar_script <(curl -s https://raw.githubusercontent.com/Danilop95/Proxmox-local/main/en.sh)
            ;;
        *)
            echo -e "${ROJO}Opción inválida.${NC}"
            sleep 2
            menu_idioma
            ;;
    esac
}

# Function to execute the selected script
ejecutar_script() {
    local script="$1"
    chmod +x "$script"
    bash "$script"
}

# Run the language selection menu
menu_idioma