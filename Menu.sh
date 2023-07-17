#!/bin/bash

# Verificar si se está ejecutando como administrador
if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ser ejecutado como administrador."
    exit 1
fi

# Función para ejecutar el script Repositorios-sources_list.sh
function ejecutar_menu() {
    echo "Ejecutando el script Repositorios-sources_list.sh..."
    bash Proxmox-local/Scripts/Repositorios-sources_list.sh
}

# Función para ejecutar el script Generico.sh
function ejecutar_generico() {
    echo "Ejecutando el script Generico.sh..."
    bash Proxmox-local/Scripts/GPU-Passthrough/Generico.sh
}

# Asignar permisos de ejecución a los scripts necesarios
function asignar_permisos() {
    echo "Asignando permisos de ejecución a los scripts..."
    chmod +x /ruta/a/Proxmox-local/Scripts/Repositorios-sources_list.sh
    chmod +x /ruta/a/Proxmox-local/Scripts/GPU-Passthrough/Generico.sh
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
            asignar_permisos
            ejecutar_menu
            ;;
        2)
            asignar_permisos
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
