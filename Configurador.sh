#!/bin/bash

# Colors
ROJO='\e[0;91m'
VERDE='\e[0;92m'
AZUL='\e[0;94m'
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
            script_espanol
            ;;
        2)
            echo -e "${AZUL}Selected: English${NC}"
            sleep 2
            script_english
            ;;
        *)
            echo -e "${ROJO}Opción inválida.${NC}"
            sleep 2
            menu_idioma
            ;;
    esac
}

# Function for Spanish script
script_espanol() {
    # Coloca aquí el contenido del script en español
    echo -e "${VERDE}¡Has seleccionado el script en español!${NC}"
}

# Function for English script
script_english() {
    # Put the content of the English script here
    echo -e "${VERDE}You have selected the script in English!${NC}"
}

# Run the language selection menu
menu_idioma
