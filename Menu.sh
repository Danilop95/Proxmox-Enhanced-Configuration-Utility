#!/bin/bash

# Función para ejecutar el script Menu.sh
function ejecutar_menu() {
    echo "Ejecutando el script Menu.sh..."
    bash /ruta/a/Proxmox-local/Scripts/Menu.sh
}

# Función para ejecutar el script Generico.sh
function ejecutar_generico() {
    echo "Ejecutando el script Generico.sh..."
    bash /ruta/a/Proxmox-local/Scripts/GPU-Passthrough/Generico.sh
}

# Mostrar el menú de selección
function mostrar_menu() {
    clear
    echo "Menú de selección:"
    echo "1. Ejecutar el script Menu.sh"
    echo "2. Ejecutar el script Generico.sh"
    echo "0. Salir"
    echo ""
}

# Bucle principal
while true; do
    mostrar_menu

    # Leer la opción seleccionada
    read -p "Ingrese el número de opción: " opcion
    echo ""

    # Evaluar la opción seleccionada
    case $opcion in
        1)
            ejecutar_menu
            ;;
        2)
            ejecutar_generico
            ;;
        0)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "Opción inválida. Por favor, ingrese un número de opción válido."
            ;;
    esac

    # Pausa antes de volver a mostrar el menú
    read -p "Presione Enter para continuar..."
done
