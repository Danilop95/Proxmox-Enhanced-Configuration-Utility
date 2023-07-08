#!/bin/bash

# Función para agregar una entrada a un archivo si no está presente
add_to_file_if_not_present() {
    local filename="$1"
    local entry="$2"
    if ! grep -Fxq "$entry" "$filename"; then
        echo "$entry" | sudo tee -a "$filename"
    fi
}

# Función para leer el tipo de CPU
read_cpu_type() {
    echo "¿Qué tipo de CPU tienes? (Intel/AMD):"
    read CPU_TYPE
    CPU_TYPE=$(echo "$CPU_TYPE" | tr '[:upper:]' '[:lower:]')
}

# Función para leer el ID del GPU
read_gpu_id() {
    echo "Por favor, introduce el nombre del dispositivo que estás buscando:"
    read DEVICE_NAME
    echo "Estos son los dispositivos que coinciden con su búsqueda:"
    lspci -v | grep -i "$DEVICE_NAME"
    echo "Ingrese la ID del dispositivo de video (formato xx:xx.x):"
    read GPU_ID
}

# Llamada a las funciones para leer los datos del usuario
read_cpu_type
read_gpu_id

# Configuración de Grub
if [[ $CPU_TYPE == "intel" ]]
then
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"/' /etc/default/grub
else
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on"/' /etc/default/grub
fi
sudo update-grub

# Módulos VFIO
add_to_file_if_not_present "/etc/modules" "vfio"
add_to_file_if_not_present "/etc/modules" "vfio_iommu_type1"
add_to_file_if_not_present "/etc/modules" "vfio_pci"
add_to_file_if_not_present "/etc/modules" "vfio_virqfd"

# Interrupción IOMMU
echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" | sudo tee -a /etc/modprobe.d/iommu_unsafe_interrupts.conf
echo "options kvm ignore_msrs=1" | sudo tee -a /etc/modprobe.d/kvm.conf

# Lista negra de controladores
add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist radeon"
add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist nouveau"
add_to_file_if_not_present "/etc/modprobe.d/blacklist.conf" "blacklist nvidia"

# Obtención de las ID del proveedor
GPU_VENDOR_ID=$(lspci -n -s "$GPU_ID" | awk '{print $3}')

# Adición del ID del proveedor a VFIO
echo "options vfio-pci ids=$GPU_VENDOR_ID disable_vga=1" | sudo tee /etc/modprobe.d/vfio.conf

# Actualización de initramfs
sudo update-initramfs -u

# Opción de reinicio
echo "¿Quieres reiniciar ahora? (s/n)"
read REBOOT
REBOOT=$(echo "$REBOOT" | tr '[:upper:]' '[:lower:]')
if [[ $REBOOT == "s" ]]; then
    sudo reboot
fi
