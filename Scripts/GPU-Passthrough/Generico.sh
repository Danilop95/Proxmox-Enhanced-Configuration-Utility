#!/bin/bash

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
    echo "Por favor, introduce el nombre del dispositivo que estás buscando (ejemplo: GTX 1080):"
    read dispositivo
    lspci -v | grep -i "$dispositivo"
}

# Función para leer el ID del GPU
read_gpu_id() {
    echo "Ingrese la ID del dispositivo de video (formato xx:xx.x):"
    read GPU_ID
    echo "Obteniendo la ID de su GPU:"
    GPU_VENDOR_ID=$(lspci -n -s "$GPU_ID" | awk '{print $3}')
    echo $GPU_VENDOR_ID
}

# Función para verificar si IOMMU está habilitado
verify_iommu() {
    echo "Verificando si IOMMU está habilitado..."
    dmesg | grep -e DMAR -e IOMMU
}

# Función para agregar opciones de MSI a la configuración de audio
add_msi_options() {
    echo "Agregando opciones de MSI para dispositivos de audio..."
    add_to_file_if_not_present "/etc/modprobe.d/snd-hda-intel.conf" "options snd-hda-intel enable_msi=1"
}

# Función para preguntar si se quiere reiniciar
ask_reboot() {
    read -p "¿Quieres reiniciar ahora? (s/n) " RESPUESTA
    case $RESPUESTA in
        [sS])
            echo "Reiniciando el sistema..."
            sudo reboot
            ;;
        *)
            echo "Por favor, recuerda reiniciar el sistema manualmente."
            ;;
    esac
}

# Función para aplicar la configuración del kernel
apply_kernel_config() {
    echo "Aplicando configuración del kernel..."
    sudo update-initramfs -u -k all
}

# Script principal

# Habilitar IOMMU en GRUB
echo "Seleccione el tipo de su CPU (1 para Intel, 2 para AMD):"
select CPU_TYPE in Intel AMD
do
    case $CPU_TYPE in
        Intel)
            sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"/' /etc/default/grub
            break
            ;;
        AMD)
            sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"/' /etc/default/grub
            break
            ;;
        *)
            echo "Por favor, seleccione 1 o 2."
            ;;
    esac
done
sudo update-grub

# Añadir módulos requeridos
add_to_file_if_not_present "/etc/modules" "vfio"
add_to_file_if_not_present "/etc/modules" "vfio_iommu_type1"
add_to_file_if_not_present "/etc/modules" "vfio_pci"
add_to_file_if_not_present "/etc/modules" "vfio_virqfd"

# Añadir opciones de VFIO e IOMMU
add_to_file_if_not_present "/etc/modprobe.d/iommu_unsafe_interrupts.conf" "options vfio_iommu_type1 allow_unsafe_interrupts=1"
add_to_file_if_not_present "/etc/modprobe.d/kvm.conf" "options kvm ignore_msrs=1"

# Añadir controladores a la lista negra
add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist radeon"
add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist nouveau"
add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist nvidia"

# Buscar GPU y leer su ID
search_gpu_device
read_gpu_id
add_to_file_if_not_present "/etc/modprobe.d/vfio.conf" "options vfio-pci ids=$GPU_VENDOR_ID disable_vga=1"

apply_kernel_config

verify_iommu
add_msi_options

ask_reboot
