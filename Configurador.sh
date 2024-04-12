#!/bin/bash

# Colors
ROJO='\e[0;31m'
VERDE='\e[0;32m'
AZUL='\e[0;34m'
NC='\e[0m' # No Color

# Determine execution context
if [[ "${BASH_SOURCE[0]}" =~ /dev/fd/ ]]; then
    echo "Running remotely."
    CONTEXT="Remoto"
    SCRIPT_DIR="https://raw.githubusercontent.com/Danilop95/Proxmox-local/main"
else
    echo "Running locally."
    CONTEXT="Local"
    SCRIPT_DIR=$(dirname "$(realpath "$0")")
fi

# Function to display language selection menu
menu_idioma() {
    clear
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}|  Seleccione el Idioma/Select Language [${CONTEXT}] |${NC}"
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${VERDE} 1) Español${NC}"
    echo -e "${VERDE} 2) English${NC}"
    echo -e "${AZUL}=================================================${NC}"
    while true; do
        read -p "$(echo -e ${AZUL}Seleccione una opción:${NC} )" opcion

        case $opcion in
            1)
                echo -e "${AZUL}Seleccionado: Español${NC}"
                sleep 2
                ejecutar_script "es.sh"
                break
                ;;
            2)
                echo -e "${AZUL}Selected: English${NC}"
                sleep 2
                ejecutar_script "en.sh"
                break
                ;;
            *)
                echo -e "${ROJO}Opción inválida.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Function to execute the selected script
ejecutar_script() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    local script=$(mktemp)

    if [[ $SCRIPT_DIR =~ ^https?:// ]]; then
        # Running remotely, use curl to download the script
        if curl -s "$script_path" -o "$script"; then
            chmod +x "$script"
            bash "$script"
        else
            echo -e "${ROJO}Error al descargar el script.${NC}"
        fi
    else
        # Running locally, execute the script directly
        if [ -f "$script_path" ]; then
            chmod +x "$script_path"
            bash "$script_path"
        else
            echo -e "${ROJO}Error: El script no se encuentra en la ruta local ${script_path}.${NC}"
        fi
    fi
}

# Run the language selection menu
menu_idioma
