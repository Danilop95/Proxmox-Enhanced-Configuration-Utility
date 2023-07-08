#!/bin/bash

# Paso 1: Configurar el Grub
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on"/' /etc/default/grub
sudo update-grub

# Paso 2: modulos VFIO
echo 'vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd' | sudo tee -a /etc/modules

# Paso 3: IOMMU interrumpe la reasignacion
echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" | sudo tee -a /etc/modprobe.d/iommu_unsafe_interrupts.conf
echo "options kvm ignore_msrs=1" | sudo tee -a /etc/modprobe.d/kvm.conf

# Paso 4: Controladores de lista negra
echo "blacklist radeon" | sudo tee -a /etc/modprobe.d/blacklist.conf
echo "blacklist nouveau" | sudo tee -a /etc/modprobe.d/blacklist.conf
echo "blacklist nvidia" | sudo tee -a /etc/modprobe.d/blacklist.conf

# Reinicio
sudo reboot
