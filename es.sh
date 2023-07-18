#!/bin/bash

# Colores
ROJO='\e[0;31m'
VERDE='\e[0;32m'
AZUL='\e[0;34m'
AMARILLO='\e[0;33m'
NC='\e[0m' # No Color

# Ruta del directorio de backup
DIRECTORIO_BACKUP="$(dirname "$0")/backup-script"

# Comprobar si el usuario es root
if [[ $EUID -ne 0 ]]; then
    echo -e "${ROJO}Este script debe ser ejecutado como root.${NC}"
    exit 1
fi

# Comprobar si sudo está instalado, si no, instalarlo.
if ! command -v sudo &> /dev/null; then
    echo -e "${AZUL}sudo no está instalado. Instalando...${NC}"
    apt-get update
    apt-get install sudo -y
fi

# Función para preguntar si se desea continuar
preguntar_continuar() {
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}| El siguiente paso consistirá en:             |${NC}"
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${VERDE}$1${NC}"
    echo -e "${AZUL}-------------------------------------------------${NC}"
    echo -n -e "${AZUL}¿Deseas continuar?${NC} (s/n): "
    read respuesta
    case $respuesta in
        [sS])
            echo -e "${AZUL}Continuando...${NC}"
            ;;
        *)
            echo -e "${ROJO}Saltando al siguiente paso.${NC}"
            return 1
            ;;
    esac
}

# Función para crear una copia de seguridad del archivo
crear_backup() {
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}| Creando una copia de seguridad de sources.list |${NC}"
    echo -e "${AZUL}=================================================${NC}"

    # Verificar si el directorio de backup existe
    if [[ ! -d "$DIRECTORIO_BACKUP" ]]; then
        mkdir -p "$DIRECTORIO_BACKUP"
        echo -e "${VERDE}Directorio de backup creado en $DIRECTORIO_BACKUP.${NC}"
    fi

    # Limitar el número máximo de backups a 5
    archivos_backup=("${DIRECTORIO_BACKUP}/sources.list.bak_"*)
    if [[ ${#archivos_backup[@]} -ge 5 ]]; then
        echo -e "${AZUL}Se ha alcanzado el número máximo de backups. Elimina algunos backups para hacer nuevos.${NC}"
        return 1
    fi

    archivo_backup="${DIRECTORIO_BACKUP}/sources.list.bak_$(date +%Y%m%d_%H%M%S)"
    sudo cp "/etc/apt/sources.list" "$archivo_backup"
    echo -e "${VERDE}Copia de seguridad creada en $archivo_backup.${NC}"
}

# Función para recuperar una copia anterior del archivo
restaurar_backup() {
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}| Recuperando una copia anterior de sources.list |${NC}"
    echo -e "${AZUL}=================================================${NC}"
    archivos_backup=("${DIRECTORIO_BACKUP}/sources.list.bak_"*)

    if [[ ${#archivos_backup[@]} -eq 0 ]]; then
        echo -e "${ROJO}No hay copias de seguridad disponibles.${NC}"
        return 1
    fi

    echo -e "${AZUL}Selecciona una copia de seguridad para restaurar:${NC}"
    for ((i=0; i<${#archivos_backup[@]}; i++)); do
        echo -e "${AZUL} $((i+1)))${NC} ${archivos_backup[$i]}"
    done

    read -p "$(echo -e ${AZUL}Ingresa el número de la copia de seguridad:${NC} )" numero_backup

    # Verificar si el número de backup es válido
    if ! [[ "$numero_backup" =~ ^[1-5]$ ]]; then
        echo -e "${ROJO}Opción inválida.${NC}"
        return 1
    fi

    archivo_backup="${archivos_backup[$((numero_backup-1))]}"
    if [[ -f "$archivo_backup" ]]; then
        echo -e "${AZUL)Vista previa del archivo de backup:${NC}"
        echo "-----------------------------------------"
        cat "$archivo_backup"
        echo "-----------------------------------------"
        echo -n -e "${AZUL}¿Deseas restaurar esta copia de seguridad?${NC} (s/n): "
        read respuesta
        case $respuesta in
            [sS])
                sudo cp "$archivo_backup" "/etc/apt/sources.list"
                echo -e "${VERDE}Copia de seguridad restaurada.${NC}"
                ;;
            *)
                echo -e "${ROJO}Operación cancelada.${NC}"
                ;;
        esac
    else
        echo -e "${ROJO}El archivo de backup no existe.${NC}"
    fi
}

# Función para abrir el archivo sources.list con nano
abrir_sources_list() {
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}| Abriendo el archivo sources.list con nano      |${NC}"
    echo -e "${AZUL}=================================================${NC}"
    sudo nano "/etc/apt/sources.list"
}

# Función para verificar si una línea existe en el archivo sources.list
linea_existe() {
    local linea="$1"
    grep -Fxq "$linea" "/etc/apt/sources.list"
}

# Función para modificar el archivo sources.list
modificar_sources_list() {
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}| Modificando el archivo sources.list            |${NC}"
    echo -e "${AZUL}=================================================${NC}"

    # Verificar si las líneas ya existen antes de agregarlas
    if linea_existe "deb http://ftp.debian.org/debian bullseye main contrib" && \
       linea_existe "deb http://ftp.debian.org/debian bullseye-updates main contrib" && \
       linea_existe "deb http://security.debian.org/debian-security bullseye-security main contrib" && \
       linea_existe "# PVE pve-no-subscription repository provided by proxmox.com, NOT recommended for production use" && \
       linea_existe "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription"
    then
        echo -e "${VERDE}El archivo sources.list ya contiene las modificaciones.${NC}"
    else
        # Agregar repositorios de Debian
        echo "deb http://ftp.debian.org/debian bullseye main contrib" | sudo tee -a "/etc/apt/sources.list"
        echo "deb http://ftp.debian.org/debian bullseye-updates main contrib" | sudo tee -a "/etc/apt/sources.list"
        echo "deb http://security.debian.org/debian-security bullseye-security main contrib" | sudo tee -a "/etc/apt/sources.list"

        # Agregar repositorio de Proxmox VE
        echo "# PVE pve-no-subscription repository provided by proxmox.com, NOT recommended for production use" | sudo tee -a "/etc/apt/sources.list"
        echo "deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription" | sudo tee -a "/etc/apt/sources.list"

        echo -e "${VERDE}Archivo sources.list modificado.${NC}"
    fi
}

# Función para agregar opciones de MSI al archivo de configuración de audio
agregar_opciones_msi() {
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}| Agregando opciones de MSI para audio           |${NC}"
    echo -e "${AZUL}=================================================${NC}"
    agregar_al_archivo_si_no_existe "/etc/modprobe.d/snd-hda-intel.conf" "options snd-hda-intel enable_msi=1"
    echo -e "${VERDE}Opciones de MSI agregadas.${NC}"
}

# Función para verificar si IOMMU está habilitado
verificar_iommu() {
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}| Verificando si IOMMU está habilitado           |${NC}"
    echo -e "${AZUL}=================================================${NC}"
    dmesg | grep -e DMAR -e IOMMU
}

# Función para aplicar la configuración del kernel
aplicar_configuracion_kernel() {
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}| Aplicando configuración del kernel             |${NC}"
    echo -e "${AZUL}=================================================${NC}"
    sudo update-initramfs -u -k all
    echo -e "${VERDE}Configuración del kernel aplicada.${NC}"
}

# Función para preguntar si se quiere reiniciar
preguntar_reinicio() {
    echo -e "${AZUL}=================================================${NC}"
    echo -n -e "${AZUL}¿Quieres reiniciar ahora?${NC} (s/n): "
    read respuesta
    case $respuesta in
        [sS])
            echo -e "${AZUL}Reiniciando el sistema...${NC}"
            sudo reboot
            ;;
        *)
            echo -e "${AZUL}Por favor, recuerda reiniciar el sistema manualmente.${NC}"
            ;;
    esac
}

# Función para agregar una entrada a un archivo si no está presente
agregar_al_archivo_si_no_existe() {
    local archivo="$1"
    local entrada="$2"
    if ! grep -Fxq "$entrada" "$archivo"; then
        echo "$entrada" | sudo tee -a "$archivo"
    fi
}

# Función para buscar el dispositivo GPU
buscar_dispositivo_gpu() {
    echo -e "${AZUL}Por favor, introduce el nombre del dispositivo que estás buscando (ejemplo: GTX 1080):${NC}"
    read dispositivo
    lspci -v | grep -i "$dispositivo"
}

# Función para leer el ID del GPU
leer_id_gpu() {
    echo -e "${AZUL}Ingrese la ID del dispositivo de video (formato xx:xx.x):${NC}"
    read ID_GPU
    echo -e "${AZUL}Obteniendo la ID de su GPU:${NC}"
    VENDEDOR_GPU=$(lspci -n -s "$ID_GPU" | awk '{print $3}')
    echo $VENDEDOR_GPU
}

# Función para configurar el passthrough de GPU
configurar_passthrough_gpu() {
    echo -e "${AZUL}=================================================${NC}"
    echo -e "${AZUL}|        Configuración GPU Passthrough           |${NC}"
    echo -e "${AZUL}=================================================${NC}"

    # Buscar GPU y leer su ID
    buscar_dispositivo_gpu
    leer_id_gpu

    # Añadir controladores a la lista negra
    agregar_al_archivo_si_no_existe "/etc/modprobe.d/blacklist.conf" "blacklist nouveau"
    agregar_al_archivo_si_no_existe "/etc/modprobe.d/blacklist.conf" "blacklist nvidia"

    # Agregar opciones de VFIO e IOMMU
    agregar_al_archivo_si_no_existe "/etc/modprobe.d/vfio.conf" "options vfio-pci ids=$VENDEDOR_GPU disable_vga=1"

    aplicar_configuracion_kernel

    preguntar_reinicio
}

# Función principal del script
principal() {
    while true; do
        clear
        echo -e "${AZUL}=================================================${NC}"
        echo -e "${AZUL}|           Menú de Opciones                    |${NC}"
        echo -e "${AZUL}=================================================${NC}"
        echo -e "${AZUL} 1) Instalación de dependencias${NC}"
        echo -e "${AZUL} 2) Configuración GPU Passthrough${NC}"
        echo -e "${AZUL} 3) Salir${NC}"
        echo -e "${AZUL}=================================================${NC}"
        read -p "$(echo -e ${AZUL}Selecciona una opción:${NC} )" opcion

        case $opcion in
            1)
                while true; do
                    clear
                    echo -e "${AZUL}=================================================${NC}"
                    echo -e "${AZUL}|    Menú de Opciones (Instalación dependencias) |${NC}"
                    echo -e "${AZUL}=================================================${NC}"
                    echo -e "${AZUL} 1) Hacer una copia de seguridad de sources.list${NC}"
                    echo -e "${AZUL} 2) Recuperar una copia anterior de sources.list${NC}"
                    echo -e "${AZUL} 3) Modificar archivo sources.list${NC}"
                    echo -e "${AZUL} 4) Abrir sources.list con nano${NC}"
                    echo -e "${AZUL} 5) Volver al menú principal${NC}"
                    echo -e "${AZUL}=================================================${NC}"
                    read -p "$(echo -e ${AZUL}Selecciona una opción:${NC} )" opcion_deps

                    case $opcion_deps in
                        1)
                            crear_backup
                            sleep 2
                            ;;
                        2)
                            restaurar_backup
                            sleep 2
                            ;;
                        3)
                            modificar_sources_list
                            sleep 2
                            ;;
                        4)
                            abrir_sources_list
                            sleep 2
                            ;;
                        5)
                            break
                            ;;
                        *)
                            echo -e "${ROJO}Opción inválida.${NC}"
                            sleep 2
                            ;;
                    esac
                done
                ;;
            2)
                configurar_passthrough_gpu
                ;;
            3)
                exit
                ;;
            *)
                echo -e "${ROJO}Opción inválida.${NC}"
                ;;
        esac
    done
}

# Ejecutar el script
principal
