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

# Función para verificar si se admite el remapeo de interrupciones
verify_interrupt_remap() {
    echo "Verificando si el remapeo de interrupciones está habilitado..."
    dmesg | grep 'remapping'
}

# Función para verificar el aislamiento de IOMMU
verify_iommu_isolation() {
    echo "Verificando el aislamiento de IOMMU..."
    pvesh get /nodes/{nodename}/hardware/pci --pci-class-blacklist ""
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

# Script principal

# 1. Selección de CPU
echo "Seleccione el tipo de su CPU (1 para Intel, 2 para AMD):"
select CPU_TYPE in Intel AMD
do
    case $CPU_TYPE in
        Intel)
            sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"/' /etc/default/grub
            break
            ;;
        AMD)
            sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on"/' /etc/default/grub
            break
            ;;
        *)
            echo "Por favor, seleccione 1 o 2."
            ;;
    esac
done
sudo update-grub

# Añadiendo módulos
add_to_file_if_not_present "/etc/modules" "vfio"
add_to_file_if_not_present "/etc/modules" "vfio_iommu_type1"
add_to_file_if_not_present "/etc/modules" "vfio_pci"
add_to_file_if_not_present "/etc/modules" "vfio_virqfd"

# Configurando opciones de VFIO e IOMMU
add_to_file_if_not_present "/etc/modprobe.d/iommu_unsafe_interrupts.conf" "options vfio_iommu_type1 allow_unsafe_interrupts=1"
add_to_file_if_not_present "/etc/modprobe.d/kvm.conf" "options kvm ignore_msrs=1"

# Añadiendo controladores a la lista negra
add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist radeon"
add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist nouveau"
add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist nvidia"

# Buscando GPU y leyendo su ID
search_gpu_device
read_gpu_id
add_to_file_if_not_present "/etc/modprobe.d/vfio.conf" "options vfio-pci ids=$GPU_VENDOR_ID disable_vga=1"

sudo update-initramfs -u

verify_iommu
verify_interrupt_remap
verify_iommu_isolation
add_msi_options

ask_reboot
