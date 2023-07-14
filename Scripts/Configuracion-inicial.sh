#!/bin/bash

# Comprobar si el usuario es root
if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ser ejecutado como root."
    exit 1
fi

# Comprobar si sudo está instalado, si no, instalarlo.
if ! command -v sudo &> /dev/null; then
    echo "sudo no está instalado. Instalando..."
    apt-get update
    apt-get install sudo -y
fi

# Función para preguntar si se desea continuar
ask_continue() {
    echo "El siguiente paso consistirá en:"
    case $1 in
        "backup")
            echo "Hacer una copia de seguridad de tu archivo sources.list."
            ;;
        "modify")
            echo "Modificar el archivo sources.list."
            ;;
        "update")
            echo "Actualizar el sistema."
            ;;
        "install")
            echo "Instalar herramientas necesarias."
            ;;
        "clone")
            echo "Clonar repositorios necesarios."
            ;;
        "install_rust")
            echo "Instalar Rust."
            ;;
        "install_pve")
            echo "Descargar e instalar los encabezados de Proxmox VE."
            ;;
    esac

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

# Función para crear una copia de seguridad del archivo
backup_file() {
    echo "Creando una copia de seguridad de tu archivo sources.list..."
    backup_filename="/etc/apt/sources.list.bak_$(date +%Y%m%d_%H%M%S)"
    sudo cp "/etc/apt/sources.list" "$backup_filename"
    echo "Copia de seguridad creada en $backup_filename."
}

# Función para modificar el archivo sources.list
modify_sources_list() {
    echo "Modificando el archivo sources.list..."
    
    # Borrar el contenido actual del archivo
    sudo echo "" > "/etc/apt/sources.list"

    # Añadir las entradas al archivo
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" | sudo tee -a "/etc/apt/sources.list"
    echo "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription" | sudo tee -a "/etc/apt/sources.list"

    # Eliminar el directorio de repositorio Enterprise si existe
    if [ -d /etc/apt/sources.list.d/ ]; then
        sudo rm -rf /etc/apt/sources.list.d/
    fi

    echo "Archivo sources.list modificado."
}

# Ejecutar las funciones
ask_continue "backup" && backup_file
ask_continue "modify" && modify_sources_list

# Continuar con la instalación de dependencias
echo 'Instalación de dependencias...'
ask_continue "update" || exit

# Actualizar el sistema
echo "Actualizando el sistema..."
sudo apt update && sudo apt -y upgrade
ask_continue "install" || exit

# Instalar herramientas necesarias
echo "Instalando herramientas necesarias..."
sudo apt -y install git build-essential pve-headers dkms jq mdevctl
ask_continue "clone" || exit

# Clonar repositorios necesarios
echo "Clonando repositorios necesarios..."
git clone https://github.com/DualCoder/vgpu_unlock
git clone https://github.com/mbilker/vgpu_unlock-rs
ask_continue "install_rust" || exit

# Instalar Rust
echo "Instalando Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
ask_continue "install_pve" || exit

# Descargar e instalar los encabezados de Proxmox VE
echo "Descargando e instalar los encabezados de Proxmox VE..."
wget http://download.proxmox.com/debian/dists/bullseye/pve-no-subscription/binary-amd64/pve-headers-5.15.30-2-pve_5.15.30-3_amd64.deb
sudo dpkg -i pve-headers-5.15.30-2-pve_5.15.30-3_amd64.deb

# Informar al usuario sobre la necesidad de descargar manualmente el controlador de nVidia vGPU
echo "Descargue el controlador v14.0 nVidia vGPU para Linux KVM desde https://nvid.nvidia.com"
echo "Necesitará solicitar una prueba de 90 días para tener acceso a los controladores. Se requiere una dirección de correo electrónico comercial."
echo "El archivo necesario del archivo ZIP es 'NVIDIA-Linux-x86_64-510.47.03-vgpu-kvm.run'"
