<h1 align="center">
  <img src="doc/img/Logo-PECU.png" width="150" alt="PECU logo"/>
  <br>
  Proxmox-Enhanced-Configuration-Utility<br><sub>( PECU )</sub>
</h1>
## Features

| Category              | Highlights                                                                               |
| --------------------- | ---------------------------------------------------------------------------------------- |
| **Repositories**      | Backup / restore `sources.list`, add "non-subscription" repo, edit with Nano.            |
| **GPU Passthrough**   | Wizard-style setup for NVIDIA, AMD, Intel; supports driverctl override; rollback option. |
| **Kernel Tweaks**     | Add `pcie_acs_override`, `video=efifb:off`, or custom flags with risk prompts.           |
| **Multi-GPU**         | Detects multiple GPUs and lets you choose the one to passthrough.                        |
| **Intel iGPU (test)** | Experimental automatic isolation of iGPU functions.                                      |
| **VM Templates**      | Declarative YAML templates with CLI tools for common VM configurations.                  |
| **Template Validation** | JSON Schema validation and CI/CD integration for template quality assurance.           |
| **Proxmox 9.x**       | Full support for the latest Proxmox VE 9.x series with enhanced compatibility and performance optimizations. |
| **Logging**           | Detailed `/var/log/pecu.log` with timestamps and automatic log rotation.                 |="center">
  <a href="https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/actions">
    <img src="https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/actions/workflows/release.yml/badge.svg" alt="CI Status"></a>
  <a href="https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/wiki">
    <img src="https://img.shields.io/badge/wiki-up%20to%20date-blue?logo=read-the-docs" alt="Wiki"></a>
  <a href="https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/releases">
    <img src="https://img.shields.io/github/v/release/Danilop95/Proxmox-Enhanced-Configuration-Utility?include_prereleases" alt="Latest release"></a>
  <a href="LICENSE">
    <img src="https://img.shields.io/github/license/Danilop95/Proxmox-Enhanced-Configuration-Utility" alt="License"></a>
</p>

---

## Table of Contents
- [Overview](#overview)
- [Requirements & Compatibility](#requirements--compatibility)
- [Quick Start](#quick-start)
  - [Direct execution (recommended)](#direct-execution-recommended)
  - [Offline / local install](#offline--local-install)
- [What Is the Release Selector?](#what-is-the-release-selector)
- [VM Templates System](#vm-templates-system)
- [Features](#features)
- [Community & Contribution](#community--contribution)
- [Support the Project](#support-the-project)
- [License](#license)

---

## Overview
**PECU** is a single-shell utility that makes day-to-day Proxmox VE management
as painless as possible:

* one-line installer  
* interactive menus for repositories, kernel flags, GPU passthrough, etc.  
* reversible operations (backup / rollback built-in)  
* auto-detects NVIDIA, AMD **and** Intel iGPUs out of the box  
* **NEW**: declarative VM template system with CLI management tools
* **NEW**: full Proxmox VE 9.x series support with enhanced compatibility and performance optimizations  

---

### Requirements & Compatibility

> The selector and the underlying scripts are designed for a **typical, up-to-date Proxmox host**.
> If your stack falls outside the matrix below, use at your own risk.

|                              |                                                                                                                                                                                                                                           |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Platform**                 | <img src="https://img.shields.io/badge/Proxmox VE-7.x %2F 8.x %2F 9.x-000000?style=for-the-badge&logo=proxmox&logoColor=white" alt="Proxmox 7 / 8 / 9 badge"> *(fully supports latest Proxmox VE 9.x with enhanced compatibility)*     |
| **CPU arch**                 | <img src="https://img.shields.io/badge/x86--64-required-6A737D?style=for-the-badge">                                                                                                                                                      |
| **Privileges**               | <img src="https://img.shields.io/badge/root_or_sudo-required-E74C3C?style=for-the-badge" alt="root badge">                                                                                                                                                                                                              

> **Heads-up** PECU does **not** support ARM / Raspberry Pi builds of Proxmox at this time.
> Community ports are welcome, but official testing is x86-64 only.

---


## Quick Start

### Direct execution (recommended)

> **New in 2025-05** – a tiny selector script fetches **all** tagged releases and  
> lets you launch whichever version (Stable, Beta, Experimental…) you want.

```bash
bash <(curl -sL \https://raw.githubusercontent.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/refs/heads/main/scripts/pecu_release_selector.sh)
```



#### Release Selector

<p align="center">
  <img src="doc/img/pecu_release_selector.png" width="90%" alt="PECU Release Selector - Standard View">
</p>

#### Release Selector - Premium Interface

<p align="center">
  <img src="doc/img/pecu_release_selector-premium.png" width="90%" alt="PECU Release Selector - Premium Interface">
</p>

#### PECU-Script
<p align="center">
  <img src="https://github.com/user-attachments/assets/efeeff90-543b-4905-9b42-dbcf10647129" width="90%" alt="PECU Script Interface">
</p>

---



### Offline / local install

All releases ship a `.tar.gz` bundle:

```bash
VERSION="v2025.04.14"                     # pick any tag
wget https://github.com/Danilop95/Proxmox-Enhanced-Configuration-Utility/releases/download/$VERSION/PECU-${VERSION#v}.tar.gz
tar -xzf PECU-${VERSION#v}.tar.gz
cd PECU-${VERSION#v}/src
chmod +x proxmox-configurator.sh
sudo ./proxmox-configurator.sh
```

---

## What Is the Release Selector?

* `pecu_release_selector.sh` is a **new ASCII-driven menu** I built over the last few months.
  It talks directly to the GitHub API, parses every tag, and sorts them by the
  custom **`PECU-Channel`** labels I introduced (Stable, Beta, Preview, Experimental, Nightly).
  The channels keep the list tidy and make it obvious which way the project is heading.
* Marking a build as **Experimental** instantly flags it orange in the menu,
  so I can ship rough prototypes or quick-fix versions without confusing people who only want Stable releases.
lector.
* `pecu_release_selector_old.sh` still exists **only as a shim** that `exec`s the new script — **it will be removed on _05 July 2025_**.

---

## VM Templates System

**New in 2025.08** – PECU now includes a declarative VM template system with CLI management tools.

### Template Features

* **Declarative YAML templates** for common VM configurations (Windows Gaming, Linux Workstation, Media Server)
* **JSON Schema validation** ensuring template consistency and correctness
* **CLI management** with `templatectl.sh` for listing, validating, rendering, and applying templates
* **Safe rendering** – view `qm` commands before execution with `--dry-run`
* **Storage flexibility** – supports `local-lvm`, `local`, and auto-detection
* **CI/CD ready** – GitHub Actions workflow for automatic validation

### Quick Template Usage

```bash
# List available templates
src/tools/templatectl.sh list --channel Stable

# Validate all templates
src/tools/templatectl.sh validate templates/

# Preview commands (safe, no execution)
src/tools/templatectl.sh render templates/windows/windows-gaming.yaml \
  --vmid 200 --storage-pool local-lvm --dry-run

# Apply template (creates VM)
sudo src/tools/templatectl.sh apply templates/windows/windows-gaming.yaml \
  --vmid 200 --storage-pool local-lvm
```

### Available Templates

| Template | Channel | OS Type | Description |
|----------|---------|---------|-------------|
| `windows-gaming` | Stable | win11 | Windows 11 VM optimized for gaming with GPU passthrough support |
| `linux-workstation` | Stable | l26 | Linux workstation for development and productivity |
| `media-server` | Stable | l26 | Lightweight Linux VM for media services (Plex, Jellyfin, etc.) |

See [templates/README.md](templates/README.md) for detailed documentation.

---

## Features

| Category              | Highlights                                                                               |
| --------------------- | ---------------------------------------------------------------------------------------- |
| **Repositories**      | Backup / restore `sources.list`, add “non-subscription” repo, edit with Nano.            |
| **GPU Passthrough**   | Wizard-style setup for NVIDIA, AMD, Intel; supports driverctl override; rollback option. |
| **Kernel Tweaks**     | Add `pcie_acs_override`, `video=efifb:off`, or custom flags with risk prompts.           |
| **Multi-GPU**         | Detects multiple GPUs and lets you choose the one to passthrough.                        |
| **Intel iGPU (test)** | Experimental automatic isolation of iGPU functions.                                      |
| **Logging**           | Detailed `/var/log/pecu.log` with timestamps.                                            |

---

## Community & Contribution

PECU grows through clear bug reports, well-scoped ideas, and peer-reviewed code.  
If you would like to get involved, choose the channel that best suits your needs:

| Purpose | Channel |
|---------|---------|
| **Bug reports / feature requests** | Use the GitHub [Issue tracker](../../issues). Please include the tag you were running, a concise description, and any relevant console output. |
| **Code contributions** | Fork the repository, branch from `main`, run `shellcheck`, keep commits focused, then open a Pull Request. |
| **Technical discussion and quick feedback** | Join the PECU Discord server: <https://discord.gg/euQTVNc2xg>. The server is used for informal Q&A, brainstorming future features, and sharing configuration tips. |
| **Sustained support and early-access builds** | Patreon memberships are available at <https://www.patreon.com/c/DVNILXP95>. Patrons receive preview builds, detailed implementation notes, and can vote on the development roadmap. |

---

### Support the Project

If PECU saves you time in daily operations and you wish to accelerate its development, consider a one-off donation:

<p align="center">
  <a href="https://buymeacoffee.com/danilop95ps" target="_blank">
    <img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png"
         alt="Buy Me a Coffee" height="37">
  </a>
</p>

Your support funds additional test hardware.


## License

**GPL-3.0** – see [LICENSE](LICENSE).
Feel free to fork, adapt, and share under the same terms.
