<!--
PECU-Channel: Experimental
PECU-Title: Template System Hardening and Release Safety Review
PECU-Desc: Safer VM template rendering, stronger validation, CI checks, and release/security documentation cleanup.
-->

# PECU Experimental Release - Template System Hardening

## Why this release exists

This release reduces risk in the PECU template system and aligns release
packaging, validation, and security documentation with the current project
state. It is not a Stable release because the renderer, template validation,
release workflow, and safety checks changed in structural ways.

## Main changes

- Hardened VM template rendering.
- Removed the unsafe eval-based template apply flow.
- Fixed TPM generation from `spec.storage.tpm`.
- Fixed boot disk generation to target `scsi0` instead of the bus name `scsi`.
- Corrected Proxmox network syntax for `qm`.
- Added explicit Q35 machine handling for the Windows 11 template.
- Added stricter JSON Schema validation for template input.
- Added a local repository validation script.
- Added CI coverage for template validation and dry-run rendering.
- Cleaned release packaging so the tarball contains the runnable project tree.
- Cleaned `SECURITY.md` to avoid unsupported signing or audit claims.
- Tightened release selector telemetry behavior and asset handling.

## Template system

`templatectl.sh render` and `templatectl.sh apply --dry-run` do not require a
real Proxmox host. They validate the YAML, render the `qm` plan, and print the
commands that would be used.

Real `apply` still requires a Proxmox node because it runs `qm`. Commands are
executed as argument arrays instead of shell strings. Raw `spec.vm.args` is
restricted and only accepted when `policy.allowUnsafeArgs: true` is set in the
template.

The bundled templates are marked Experimental in this release. They validate
and dry-run cleanly, but the non-dry-run VM creation path still needs testing
against real Proxmox storage and bridge combinations.

## Security notes

- Removed `eval` from the template apply path.
- Reduced command injection risk from YAML by validating VM IDs, VM names,
  bridges, storage IDs, CPU strings, disk sizes, and raw args.
- `SECURITY.md` now documents the guarantees the repository actually provides.
- Release integrity is based on `SHA256SUMS`; no GPG-signed release assets are
  claimed.

## Validation performed

The following checks passed in the maintainer workspace:

```bash
git diff --check
bash -n scripts/pecu_release_selector.sh
bash -n src/proxmox-configurator.sh
bash -n src/tools/templatectl.sh
bash -n src/tools/renderers/qm.sh
CI=true scripts/validate_repo.sh
grep -RIn --exclude-dir=.git '\beval\b' .
src/tools/templatectl.sh render templates/windows/windows-gaming.yaml \
  --vmid 200 \
  --storage-pool local-lvm \
  --dry-run
```

The Windows render output includes:

- `--machine q35`
- `--bios ovmf`
- `--bootdisk scsi0`
- `--efidisk0`
- `--tpmstate0`
- `--net0 virtio,bridge=vmbr0,firewall=1`

## Known limitations

- No real `qm create` was executed on a Proxmox node in this environment.
- ShellCheck is enforced at error severity; warning-level debt in the larger
  interactive scripts remains.
- `src/proxmox-configurator.sh` is still a large interactive Bash script. This
  release fixes targeted safety issues but does not rewrite it.
- The template schema is intentionally conservative and may reject some valid
  Proxmox edge cases until they are reviewed and added deliberately.

## Recommended testing

Run the repository validation locally:

```bash
CI=true scripts/validate_repo.sh
```

Preview the Windows template on the target host:

```bash
sudo src/tools/templatectl.sh apply templates/windows/windows-gaming.yaml \
  --vmid 200 \
  --storage-pool local-lvm \
  --dry-run
```

Only after reviewing the dry-run plan, test a real apply on a non-production
Proxmox node:

```bash
sudo src/tools/templatectl.sh apply templates/windows/windows-gaming.yaml \
  --vmid 200 \
  --storage-pool local-lvm

qm config 200
```

## Upgrade notes

Treat this as an Experimental release. Do not run it directly on production
hosts without reviewing the dry-run output, checking backups, and keeping
console or out-of-band access available.
