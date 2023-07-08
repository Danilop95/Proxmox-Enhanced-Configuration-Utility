#!/bin/bash

# Función para buscar el dispositivo GPU
search_gpu_device() {
    echo "Por favor, introduce el nombre del dispositivo que estás buscando:"
    read dispositivo
    lspci -v | grep -i "$dispositivo"
}

# Función para leer el ID del GPU
read_gpu_id() {
    echo "Ingrese la ID del dispositivo de video (formato xx:xx.x):"
    read GPU_ID
    echo "Obteniendo la ID de su GPU:"
    GPU_VENDOR_ID=$(lspci -n -s $GPU_ID | awk '{print $3}')
    echo $GPU_VENDOR_ID
}

# Función para agregar una entrada a la lista negra si no está presente
add_to_blacklist() {
    local entry="blacklist $1"
    if ! grep -Fxq "$entry" /etc/modprobe.d/blacklist.conf; then
        echo "$entry" | sudo tee -a /etc/modprobe.d/blacklist.conf
    fi
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
    echo "options snd-hda-intel enable_msi=1" | sudo tee -a /etc/modprobe.d/snd-hda-intel.conf
}

# Función para verificar si el dispositivo GPU es compatible con UEFI
verify_uefi_compatibility() {
    echo "Verificando si el dispositivo de GPU es compatible con UEFI..."
    # Agrega aquí tu código de verificación de compatibilidad con UEFI
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

echo 'vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd' | sudo tee -a /etc/modules

echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" | sudo tee -a /etc/modprobe.d/iommu_unsafe_interrupts.conf
echo "options kvm ignore_msrs=1" | sudo tee -a /etc/modprobe.d/kvm.conf

add_to_blacklist "radeon"
add_to_blacklist "nouveau"
add_to_blacklist "nvidia"

search_gpu_device
read_gpu_id
echo "options vfio-pci ids=$GPU_VENDOR_ID disable_vga=1" | sudo tee -a /etc/modprobe.d/vfio.conf

sudo update-initramfs -u

verify_iommu
verify_interrupt_remap
verify_iommu_isolation
add_msi_options
verify_uefi_compatibility

ask_reboot
