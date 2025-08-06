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

- `bash`, `jq`, `yq` (v4), `python3` con `jsonschema` y `pyyaml`.
- Host Proxmox (para `apply`), comandos `qm`/`pvesm`.

## Uso rápido

```bash
# Listar por canal
src/tools/templatectl.sh list --channel Stable

# Validar todas
src/tools/templatectl.sh validate templates/

# Ver comandos (dry-run)
src/tools/templatectl.sh render templates/windows/windows-gaming.yaml \
  --vmid 200 --storage-pool local-lvm --dry-run

# Aplicar (ejecuta qm)
sudo src/tools/templatectl.sh apply templates/windows/windows-gaming.yaml \
  --vmid 200 --storage-pool local-lvm
```

## Convenciones

* No se fuerza `--machine`; deja que Proxmox seleccione.
* En `local-lvm` se usan volúmenes LVM-thin (sin `format=`).
* En `local` (directory) se permite `format=raw`.
* No se añade ningún dispositivo USB por defecto.
* Se crean `efidisk0`/`tpmstate0` si están definidos.
