#!/bin/bash

# Verificar e instalar sudo si no está presente
if ! command -v sudo &> /dev/null
then
    echo "sudo no está instalado. Intentando instalar sudo..."
    apt-get update
    apt-get install sudo -y
fi

# Función para preguntar si se desea continuar
ask_continue() {
    read -p "¿Deseas continuar con el siguiente paso? (y/n) " answer
    case $answer in
        [yY])
            echo "Continuando..."
            ;;
        *)
            echo "Saltando al siguiente paso."
            return 1
            ;;
    esac
}

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
ask_continue && backup_file
ask_continue && modify_sources_list

# Continuar con la instalación de dependencias
echo 'Instalación de dependencias...'
ask_continue || exit

# Actualizar el sistema
echo "Actualizando el sistema..."
sudo apt update && sudo apt -y upgrade
ask_continue || exit

# Instalar herramientas necesarias
echo "Instalando herramientas necesarias..."
sudo apt -y install git build-essential pve-headers dkms jq mdevctl
ask_continue || exit

# Clonar repositorios necesarios
echo "Clonando repositorios necesarios..."
git clone https://github.com/DualCoder/vgpu_unlock
git clone https://github.com/mbilker/vgpu_unlock-rs
ask_continue || exit

# Instalar Rust
echo "Instalando Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
ask_continue || exit

# Descargar e instalar los encabezados de Proxmox VE
echo "Descargando e instalando los encabezados de Proxmox VE..."
wget http://download.proxmox.com/debian/dists/bullseye/pve-no-subscription/binary-amd64/pve-headers-5.15.30-2-pve_5.15.30-3_amd64.deb
sudo dpkg -i pve-headers-5.15.30-2-pve_5.15.30-3_amd64.deb
ask_continue || exit

# Informar al usuario sobre la necesidad de descargar manualmente el controlador de nVidia vGPU
echo "Descargue el controlador v14.0 nVidia vGPU para Linux KVM desde https://nvid.nvidia.com"
echo "Necesitará solicitar una prueba de 90 días para tener acceso a los controladores. Se requiere una dirección de correo electrónico comercial."
echo "El archivo necesario del archivo ZIP es 'NVIDIA-Linux-x86_64-510.47.03-vgpu-kvm.run'"
