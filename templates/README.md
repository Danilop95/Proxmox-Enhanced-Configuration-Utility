# Catálogo de VM Templates (PECU)

Este directorio contiene plantillas **declarativas** en YAML, validadas por **JSON Schema** y aplicables a un host Proxmox mediante el CLI `templatectl.sh`.

## Estructura

```
templates/
├── windows/
│   └── windows-gaming.yaml
├── linux/
│   ├── linux-workstation.yaml
│   └── media-server.yaml
└── schemas/
    └── template.schema.json
```

## Requisitos

- `bash`, `python3` y `PyYAML` para listar/renderizar plantillas.
- `python3-jsonschema` o el modulo Python `jsonschema` para `validate`.
- Host Proxmox solo para `apply` real; `apply --dry-run` no requiere `qm`.

## Uso rápido

```bash
# Listar por canal
src/tools/templatectl.sh list --channel Experimental

# Validar todas
src/tools/templatectl.sh validate templates/

# Ver comandos humanos seguros. No ejecuta nada.
src/tools/templatectl.sh render templates/windows/windows-gaming.yaml \
  --vmid 200 --storage-pool local-lvm

# Aplicar en modo dry-run. Muestra exactamente lo que se ejecutaria.
src/tools/templatectl.sh apply templates/windows/windows-gaming.yaml \
  --vmid 200 --storage-pool local-lvm --dry-run

# Aplicar en un host Proxmox real. Ejecuta qm sin eval ni shell intermedio.
sudo src/tools/templatectl.sh apply templates/windows/windows-gaming.yaml \
  --vmid 200 --storage-pool local-lvm
```

## Convenciones

- `apply` ejecuta arrays de argumentos, no strings con `eval`.
- `spec.vm.chipset: q35` genera `--machine q35` cuando `policy.allowMachinePin: true`.
- Si `allowMachinePin: false`, el renderer avisa y no aplica `--machine`.
- En `local-lvm` se usan volúmenes LVM-thin sin `format=`.
- En `local` (directory) se permite `format=raw` o `format=qcow2`.
- `--bootdisk` apunta al disco concreto (`scsi0`, `virtio0`, etc.).
- La red se renderiza como `virtio,bridge=vmbr0,firewall=1`.
- Se crean `efidisk0` y `tpmstate0` si están definidos.
- `spec.vm.args` solo se acepta con `policy.allowUnsafeArgs: true`.

## Validación local

```bash
scripts/validate_repo.sh
```

El validador local cubre sintaxis Bash, JSON Schema, render dry-run de todas
las plantillas, `apply --dry-run`, ausencia de `eval` ejecutable y regresiones
conocidas como `storage.tpm` sin `--tpmstate0` o `--bootdisk scsi`.

`shellcheck` y `yamllint` se ejecutan si están instalados. En CI se instalan
antes de lanzar el validador.
