#!/bin/bash

# Función para ejecutar el script Repositorios...sh
function ejecutar_menu() {
    echo "Ejecutando el script Menu.sh..."
    bash /ruta/a/Proxmox-local/Scripts/Repositorios-sources_list.sh
}

# Función para ejecutar el script Generico.sh
function ejecutar_generico() {
    echo "Ejecutando el script Generico.sh..."
    bash /Scripts/GPU-Passthrough/Generico.sh
}

# Mostrar el menú de selección
function mostrar_menu() {
    clear
    echo "Menú de selección:"
    echo "1. Instalar repositorios Proxmox"
    echo "2. Instalar y configurar GPU-Passthrough"
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
