#!/bin/bash

# Colores
RED='\e[0;31m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
YELLOW='\e[0;33m'
NC='\e[0m' # No Color

# Ruta del directorio de backup
BACKUP_DIR="$(dirname "$0")/backup-script"

# Comprobar si el usuario es root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Este script debe ser ejecutado como root.${NC}"
    exit 1
fi

# Comprobar si sudo está instalado, si no, instalarlo.
if ! command -v sudo &> /dev/null; then
    echo -e "${BLUE}sudo no está instalado. Instalando...${NC}"
    apt-get update
    apt-get install sudo -y
fi

# Función para preguntar si se desea continuar
ask_continue() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| El siguiente paso consistirá en:             |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}-------------------------------------------------${NC}"
    echo -n -e "${BLUE}¿Deseas continuar?${NC} (y/n): "
    read answer
    case $answer in
        [yY])
            echo -e "${BLUE}Continuando...${NC}"
            ;;
        *)
            echo -e "${RED}Saltando al siguiente paso.${NC}"
            return 1
            ;;
    esac
}

# Función para crear una copia de seguridad del archivo
backup_file() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Creando una copia de seguridad de sources.list |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # Verificar si el directorio de backup existe
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        echo -e "${GREEN}Directorio de backup creado en $BACKUP_DIR.${NC}"
    fi

    # Limitar el número máximo de backups a 5
    backup_files=("${BACKUP_DIR}/sources.list.bak_"*)
    if [[ ${#backup_files[@]} -ge 5 ]]; then
        echo -e "${BLUE}El número máximo de backups ha sido alcanzado. Elimina algunos backups para hacer nuevos.${NC}"
        return 1
    fi

    backup_filename="${BACKUP_DIR}/sources.list.bak_$(date +%Y%m%d_%H%M%S)"
    sudo cp "/etc/apt/sources.list" "$backup_filename"
    echo -e "${GREEN}Copia de seguridad creada en $backup_filename.${NC}"
}

# Función para recuperar una copia anterior del archivo
restore_backup() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Recuperando una copia anterior de sources.list |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    backup_files=("${BACKUP_DIR}/sources.list.bak_"*)

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo -e "${RED}No hay copias de seguridad disponibles.${NC}"
        return 1
    fi

    echo -e "${BLUE}Seleccione una copia de seguridad para restaurar:${NC}"
    for ((i=0; i<${#backup_files[@]}; i++)); do
        echo -e "${BLUE} $((i+1)))${NC} ${backup_files[$i]}"
    done

    read -p "$(echo -e ${BLUE}Ingresa el número de la copia de seguridad:${NC} )" backup_number

    # Verificar si el número de backup es válido
    if ! [[ "$backup_number" =~ ^[1-5]$ ]]; then
        echo -e "${RED}Opción inválida.${NC}"
        return 1
    fi

    backup_file="${backup_files[$((backup_number-1))]}"
    if [[ -f "$backup_file" ]]; then
        echo -e "${BLUE}Vista previa del archivo de backup:${NC}"
        echo "-----------------------------------------"
        cat "$backup_file"
        echo "-----------------------------------------"
        echo -n -e "${BLUE}¿Deseas restaurar esta copia de seguridad?${NC} (y/n): "
        read answer
        case $answer in
            [yY])
                sudo cp "$backup_file" "/etc/apt/sources.list"
                echo -e "${GREEN}Copia de seguridad restaurada.${NC}"
                ;;
            *)
                echo -e "${RED}Operación cancelada.${NC}"
                ;;
        esac
    else
        echo -e "${RED}El archivo de backup no existe.${NC}"
    fi
}

# Función para abrir el archivo sources.list con nano
open_sources_list() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Abriendo el archivo sources.list con nano      |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    sudo nano "/etc/apt/sources.list"
}

# Función para verificar si una línea existe en el archivo sources.list
line_exists() {
    local line="$1"
    grep -Fxq "$line" "/etc/apt/sources.list"
}

# Función para modificar el archivo sources.list
modify_sources_list() {
    rm -r /etc/apt/sources.list.d/* &&
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Modificando el archivo sources.list            |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # Verificar si las líneas ya existen antes de agregarlas
    if line_exists "deb http://ftp.debian.org/debian bullseye main contrib" && \
       line_exists "deb http://ftp.debian.org/debian bullseye-updates main contrib" && \
       line_exists "deb http://security.debian.org/debian-security bullseye-security main contrib" && \
       line_exists "# PVE pve-no-subscription repository provided by proxmox.com, NOT recommended for production use" && \
       line_exists "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription"
    then
        echo -e "${GREEN}El archivo sources.list ya contiene las modificaciones.${NC}"
    else
        # Agregar repositorios de Debian
        echo "deb http://ftp.debian.org/debian bullseye main contrib" | sudo tee -a "/etc/apt/sources.list"
        echo "deb http://ftp.debian.org/debian bullseye-updates main contrib" | sudo tee -a "/etc/apt/sources.list"
        echo "deb http://security.debian.org/debian-security bullseye-security main contrib" | sudo tee -a "/etc/apt/sources.list"

        # Agregar repositorio de Proxmox VE
        echo "# PVE pve-no-subscription repository provided by proxmox.com, NOT recommended for production use" | sudo tee -a "/etc/apt/sources.list"
        echo "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription" | sudo tee -a "/etc/apt/sources.list"

        echo -e "${GREEN}Archivo sources.list modificado.${NC}"
    fi
}

# Función para agregar opciones de MSI al archivo de configuración de audio
add_msi_options() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Agregando opciones de MSI para audio           |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    add_to_file_if_not_present "/etc/modprobe.d/snd-hda-intel.conf" "options snd-hda-intel enable_msi=1"
    echo -e "${GREEN}Opciones de MSI agregadas.${NC}"
}

# Función para verificar si IOMMU está habilitado
verify_iommu() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Verificando si IOMMU está habilitado           |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    dmesg | grep -e DMAR -e IOMMU
}

# Función para aplicar la configuración del kernel
apply_kernel_config() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}| Aplicando configuración del kernel             |${NC}"
    echo -e "${BLUE}=================================================${NC}"
    sudo update-initramfs -u -k all
    echo -e "${GREEN}Configuración del kernel aplicada.${NC}"
}

# Función para preguntar si se quiere reiniciar
ask_reboot() {
    echo -e "${BLUE}=================================================${NC}"
    echo -n -e "${BLUE}¿Quieres reiniciar ahora?${NC} (s/n): "
    read answer
    case $answer in
        [sS])
            echo -e "${BLUE}Reiniciando el sistema...${NC}"
            sudo reboot
            ;;
        *)
            echo -e "${BLUE}Por favor, recuerda reiniciar el sistema manualmente.${NC}"
            ;;
    esac
}

# Función para agregar una entrada a un archivo si no está presente
add_to_file_if_not_present() {
    local filename="$1"
    local entry="$2"
    if ! grep -Fxq "$entry" "$filename"; then
        echo "$entry" | sudo tee -a "$filename"
    fi
}

# Función para buscar el dispositivo GPU
search_gpu_device() {
    echo -e "${BLUE}Por favor, introduce el nombre del dispositivo que estás buscando (ejemplo: GTX 1080):${NC}"
    read dispositivo
    lspci -v | grep -i "$dispositivo"
}

# Función para leer el ID del GPU
read_gpu_id() {
    echo -e "${BLUE}Ingrese la ID del dispositivo de video (formato xx:xx.x):${NC}"
    read GPU_ID
    echo -e "${BLUE}Obteniendo la ID de su GPU:${NC}"
    GPU_VENDOR_ID=$(lspci -n -s "$GPU_ID" | awk '{print $3}')
    echo $GPU_VENDOR_ID
}

# Función para configurar el passthrough de GPU
configure_gpu_passthrough() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}|        Configuración GPU Passthrough           |${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # Buscar GPU y leer su ID
    search_gpu_device
    read_gpu_id

    # Añadir controladores a la lista negra
    add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist nouveau"
    add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist nvidia"

    # Agregar opciones de VFIO e IOMMU
    add_to_file_if_not_present "/etc/modprobe.d/vfio.conf" "options vfio-pci ids=$GPU_VENDOR_ID disable_vga=1"

    apply_kernel_config

    ask_reboot
}

# Función principal del script
main() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${BLUE}|           Menú de Opciones                    |${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${BLUE} 1) Instalación de dependencias${NC}"
        echo -e "${BLUE} 2) Configuración GPU Passthrough${NC}"
        echo -e "${BLUE} 3) Salir${NC}"
        echo -e "${BLUE}=================================================${NC}"
        read -p "$(echo -e ${BLUE}Selecciona una opción:${NC} )" option

        case $option in
            1)
                while true; do
                    clear
                    echo -e "${BLUE}=================================================${NC}"
                    echo -e "${BLUE}|    Menú de Opciones (Instalación dependencias) |${NC}"
                    echo -e "${BLUE}=================================================${NC}"
                    echo -e "${BLUE} 1) Hacer una copia de seguridad de sources.list${NC}"
                    echo -e "${BLUE} 2) Recuperar una copia anterior de sources.list${NC}"
                    echo -e "${BLUE} 3) Modificar archivo sources.list${NC}"
                    echo -e "${BLUE} 4) Abrir sources.list con nano${NC}"
                    echo -e "${BLUE} 5) Volver al menú principal${NC}"
                    echo -e "${BLUE}=================================================${NC}"
                    read -p "$(echo -e ${BLUE}Selecciona una opción:${NC} )" option_deps

                    case $option_deps in
                        1)
                            backup_file
                            sleep 2
                            ;;
                        2)
                            restore_backup
                            sleep 2
                            ;;
                        3)
                            modify_sources_list
                            sleep 2
                            ;;
                        4)
                            open_sources_list
                            sleep 2
                            ;;
                        5)
                            break
                            ;;
                        *)
                            echo -e "${RED}Opción inválida.${NC}"
                            sleep 2
                            ;;
                    esac
                done
                ;;
            2)
                configure_gpu_passthrough
                ;;
            3)
                exit
                ;;
            *)
                echo -e "${RED}Opción inválida.${NC}"
                ;;
        esac
    done
}

# Ejecutar el script
main
