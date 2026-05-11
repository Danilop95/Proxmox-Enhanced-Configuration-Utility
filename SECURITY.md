# Security Policy

**Project:** Proxmox Enhanced Configuration Utility (PECU)
**Repository:** `Danilop95/Proxmox-Enhanced-Configuration-Utility`
**License:** GPL-3.0
**Last updated:** May 11, 2026

PECU is a Bash/Linux utility that can modify Proxmox host configuration as
root. Treat every release as privileged system software: review the code, keep
out-of-band console access, and test changes outside production first.

## Scope

This policy covers first-party files in this repository:

- `src/proxmox-configurator.sh`
- `scripts/pecu_release_selector.sh`
- `src/tools/templatectl.sh`
- `src/tools/renderers/qm.sh`
- `templates/`
- `.github/workflows/`
- project documentation

Third-party software such as Proxmox VE, Debian, kernel modules, GPU drivers,
`jq`, `yq`, `shellcheck`, Python packages, and GitHub infrastructure is out of
scope and should be reported upstream.

## Supported Versions

Security fixes target the current `main` branch and the latest published Stable
release when a fix can be backported safely. Older tags and experimental/beta
release channels are best-effort only.

## Reporting a Vulnerability

Preferred method:

1. Open the repository **Security** tab on GitHub.
2. Choose **Report a vulnerability**.
3. Include affected version/tag, affected file, reproduction steps, expected
   behavior, actual behavior, and impact.

If GitHub Security Advisories are unavailable, contact the maintainer through
the public GitHub profile and request a private disclosure channel. Do not file
public issues for exploitable vulnerabilities until coordinated disclosure is
agreed.

## Response Expectations

This is a small open-source project. Response is best-effort, not a guaranteed
SLA. The maintainer will try to acknowledge credible reports promptly, triage
impact, prepare a fix, and publish a release note or advisory when appropriate.

## Release Integrity

The release workflow is expected to publish:

- a `PECU-<version>.tar.gz` bundle containing the runnable project structure
- `SHA256SUMS` for release assets

Verify checksums when they are present:

```bash
sha256sum -c SHA256SUMS
```

This repository does **not** currently claim GPG-signed release assets or a
published project signing key. Do not rely on old documentation or third-party
copies that claim otherwise unless the release page explicitly provides those
artifacts.

## Safe-Use Guidance

- Prefer tagged releases over running the moving `main` branch.
- Read scripts before running them as root.
- Keep backups and console/IPMI access before changing bootloader, VFIO, or
  initramfs configuration.
- Use `src/tools/templatectl.sh apply --dry-run` before creating VMs from YAML
  templates.
- Run local validation before contributing:

```bash
scripts/validate_repo.sh
```

## Sensitive Areas

Security-sensitive changes should be reviewed carefully when they touch:

- command execution from YAML/template input
- release selector downloads or telemetry
- `/etc/modprobe.d/*.conf`
- `/etc/modules-load.d/*.conf`
- `/etc/default/grub` and `/etc/kernel/cmdline`
- VFIO device ID selection and SR-IOV PF/VF handling
- GitHub Actions release packaging
