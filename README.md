# Proxmox Local Configurado

Este repositorio contiene un script de Bash llamado `Configurador.sh` que facilita la configuración de Proxmox y la administración de los repositorios de paquetes. Proporciona opciones para respaldar, restaurar y modificar el archivo `sources.list`, así como configurar el passthrough de GPU en Proxmox.

## Funcionamiento

El script `Configurador.sh` ofrece un menú interactivo con las siguientes opciones:

- **Instalación de dependencias**: Permite realizar diversas operaciones relacionadas con el archivo `sources.list`, como hacer una copia de seguridad, restaurar una copia anterior, modificar el archivo o abrirlo con el editor Nano.
- **Configuración GPU Passthrough**: Permite configurar el passthrough de GPU en Proxmox, lo que es útil para asignar una tarjeta gráfica dedicada a una máquina virtual.
- **Salir**: Finaliza la ejecución del script.

El script también verifica si los repositorios de paquetes de Proxmox están correctamente configurados y muestra información sobre el estado de IOMMU y opciones de MSI.

## Requisitos

El script ha sido diseñado para ser utilizado en sistemas Proxmox y requiere privilegios de root para su ejecución. Además, se recomienda tener conocimientos básicos sobre la configuración de Proxmox y los repositorios de paquetes.

## Versiones de Proxmox compatibles

El script ha sido probado y es compatible con las siguientes versiones de Proxmox:

- Proxmox VE 6.x
- Proxmox VE 7.x
- Proxmox VE 8.x

## Uso

1. Clona este repositorio en tu máquina Proxmox local.
2. Asegúrate de que el archivo `Configurador.sh` tiene permisos de ejecución. Si no, puedes otorgar los permisos ejecutando `chmod +x Configurador.sh`.
3. Ejecuta el script `Configurador.sh` como usuario root utilizando el siguiente comando: `sudo ./Configurador.sh`.
4. Sigue las instrucciones del menú interactivo para realizar las operaciones deseadas.

## Contribución

Si deseas contribuir a este proyecto, puedes enviar tus sugerencias, mejoras o correcciones a través de los *issues*.


## Licencia
Este proyecto está licenciado bajo la Licencia Pública General de GNU v3.0 (GPL-3.0). Para obtener más información, consulta el archivo LICENSE.
