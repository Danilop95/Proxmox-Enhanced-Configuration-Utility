# Proxmox-Enhanced-Configuration-Utility (PECU)

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Compatible Proxmox Versions](#compatible-proxmox-versions)
- [Usage and Installation](#usage-and-installation)
- [Contribution](#contribution)
- [License](#license)

## Overview

The **Proxmox-Enhanced-Configuration-Utility (PECU)** is a powerful Bash script designed to streamline the configuration and management of Proxmox VE environments. This utility provides an interactive menu system for performing key tasks such as managing package repositories and configuring GPU passthrough, making it easier to optimize your Proxmox setup for various use cases.

## Features

The `proxmox-configurator.sh` script includes the following features:

- **Dependency Installation**:
  - **Backup and Restore**: Create and restore backups of the `sources.list` file to ensure you have safe points to revert to.
  - **Modify `sources.list`**: Edit the `sources.list` file directly within the script interface using Nano or automatically add recommended repositories.
  
- **GPU Passthrough Configuration**:
  - Automatically configure GPU passthrough to assign a dedicated graphics card to virtual machines, optimizing performance for compute-intensive tasks.

- **System Configuration Checks**:
  - Verifies if the Proxmox package repositories are correctly configured.
  - Displays the state of IOMMU and MSI options for better hardware optimization.

- **Exit Option**:
  - Safely exit the script with a clean shutdown of any operations in progress.

## Requirements

To use this script, the following are required:

- **Proxmox VE**: This script is specifically designed for use on Proxmox VE systems.
- **Root Privileges**: Must be run with root or sudo privileges to modify system configurations and perform installations.
- **Basic Proxmox Knowledge**: Familiarity with Proxmox setup and configuration is recommended for optimal use of the script's features.

## Compatible Proxmox Versions

The `proxmox-configurator.sh` script has been tested and is compatible with the following Proxmox VE versions:

- Proxmox VE 7.x
- Proxmox VE 8.x

## Usage and Installation

You can run the script directly from your Proxmox server or clone the repository and execute it locally. Follow the instructions below for each method.

### Direct Execution

To run the script directly from the internet, use the following command:

```bash
bash <(curl -s https://raw.githubusercontent.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/main/proxmox-configurator.sh)
```

> **Note**: This command requires an active internet connection and is specific to Linux systems with Bash and Curl installed.

### Local Installation

Alternatively, you can clone this repository and run the script from your local Proxmox environment:

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility.git
   cd Proxmox-Enhanced-Configuration-Utility
   ```

2. **Set Execution Permissions**:

   Ensure the script has the necessary execution permissions. If not, grant them with:

   ```bash
   chmod +x proxmox-configurator.sh
   ```

3. **Run the Script**:

   Execute the script with root privileges:

   ```bash
   sudo ./proxmox-configurator.sh
   ```

4. **Follow the Interactive Menu**:

   The script will present an interactive menu. Follow the on-screen instructions to perform the desired operations.

### Common Commands

Here are some common commands to use with this script:

```bash
chmod +x proxmox-configurator.sh
sudo ./proxmox-configurator.sh
```

## Contribution

We welcome contributions to enhance the functionality and compatibility of this utility script. You can contribute in several ways:

- **Issues**: Report bugs or suggest new features by opening an issue on our GitHub repository.
- **Pull Requests**: Submit your improvements through a pull request. Make sure to follow the contribution guidelines in the repository.

## Support

If you find this project helpful, consider supporting us!

<a href="https://www.buymeacoffee.com/gbraad" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" style="height: 37px !important;width: 170px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>

## License

This project is licensed under the [GNU General Public License v3.0 (GPL-3.0)](LICENSE). For more information, please refer to the [LICENSE](LICENSE) file in the repository.
