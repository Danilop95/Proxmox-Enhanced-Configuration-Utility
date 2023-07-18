# Configured Proxmox Local

- [Operation](#operation)
- [Requirements](#requirements)
- [Compatible Proxmox Versions](#compatible-proxmox-versions)
- [Usage/Installation](#usage)
- [Contribution](#contribution)
- [License](#license)

This repository contains a Bash script called `Configurator.sh` that facilitates the configuration of Proxmox and the management of package repositories. It provides options to backup, restore, and modify the `sources.list` file, as well as configure GPU passthrough in Proxmox.

## Operation

The `Configurator.sh` script offers an interactive menu with the following options:

- **Dependency Installation**: Allows various operations related to the `sources.list` file, such as creating a backup, restoring a previous backup, modifying the file, or opening it with the Nano editor.
- **GPU Passthrough Configuration**: Enables GPU passthrough configuration in Proxmox, which is useful for assigning a dedicated graphics card to a virtual machine.
- **Exit**: Ends the script execution.

The script also verifies if the Proxmox package repositories are correctly configured and displays information about the state of IOMMU and MSI options.

## Requirements

The script has been designed to be used on Proxmox systems and requires root privileges for execution. Additionally, basic knowledge of Proxmox configuration and package repositories is recommended.

## Compatible Proxmox Versions

The script has been tested and is compatible with the following Proxmox versions:

- Proxmox VE 6.x
- Proxmox VE 7.x
- Proxmox VE 8.x

## Usage/Installation

⚙️To execute the script directly, you can use the following command on your Proxmox server⚙️

```bash
bash <(curl -s https://raw.githubusercontent.com/Danilop95/Proxmox-local/main/Configurador.sh)
```
### Alternatively, you can clone the repository in a traditional way:

1. Clone this repository on your local Proxmox machine.
2. Ensure that the `Configurator.sh` file has execution permissions. If not, you can grant permissions by running `chmod +x Configurator.sh`.
3. Run the `Configurator.sh` script as the root user using the following command: `sudo ./Configurator.sh`.
4. Follow the instructions in the interactive menu to perform desired operations.

## Contribution

If you wish to contribute to this project, you can submit your suggestions, improvements, or corrections through the issues.

## License

This project is licensed under the [GNU General Public License v3.0 (GPL-3.0)](LICENSE). For more information, see the [LICENSE](LICENSE).
