#!/bin/bash

# Nombre del archivo a modificar
filename="/etc/apt/sources.list"

# Función para crear una copia de seguridad del archivo
backup_file() {
    echo "Creando una copia de seguridad de tu archivo sources.list..."
    backup_filename="/etc/apt/sources.list.bak_$(date +%Y%m%d_%H%M%S)"
    sudo cp "$filename" "$backup_filename"
    echo "Copia de seguridad creada en $backup_filename."
}

# Función para modificar el archivo sources.list
modify_sources_list() {
    echo "Modificando el archivo sources.list..."
    
    # Borrar el contenido actual del archivo
    sudo echo "" > "$filename"

    # Añadir las entradas al archivo
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" | sudo tee -a "$filename"
    echo "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription" | sudo tee -a "$filename"

    # Eliminar el archivo de repositorio Enterprise si existe
    if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
        sudo rm /etc/apt/sources.list.d/pve-enterprise.list
    fi

    echo "Archivo sources.list modificado."
}

# Ejecutar las funciones
backup_file
modify_sources_list

echo "Operación completada."
