#!/usr/bin/env bash
set -euo pipefail

# templatectl.sh - CLI para listar, validar, renderizar y aplicar plantillas PECU.
# Requisitos:
#   - list/render: bash, python3, PyYAML
#   - validate:    python3, PyYAML, jsonschema
#   - apply:       qm en Proxmox real; no usa eval ni shell para ejecutar comandos

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCHEMA_PATH="${REPO_ROOT}/templates/schemas/template.schema.json"
RENDERER="${SCRIPT_DIR}/renderers/qm.sh"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_tools() {
  local missing=()
  local tool
  for tool in "$@"; do
    have "$tool" || missing+=("$tool")
  done
  if (( ${#missing[@]} )); then
    die "Faltan herramientas: ${missing[*]}"
  fi
}

usage() {
  cat <<'EOF'
templatectl.sh - gestiona VM templates (PECU)

Comandos:
  list [--channel <Stable|Beta|Experimental>] [--path <dir>]
  validate <path|file>
  render <file.yaml> --vmid <id> [--storage-pool <auto|pool>] [--disk-size <GiB>] [--dry-run]
  apply  <file.yaml> --vmid <id> [--storage-pool <auto|pool>] [--disk-size <GiB>] [--no-convert-template] [--dry-run]

Flags comunes:
  --vmid N                 VMID obligatorio para render/apply (100-999999999)
  --storage-pool NAME      Fuerza pool (por defecto: valor de YAML o auto)
  --disk-size GiB          Sobrescribe tamano de disco de arranque
  --dry-run                No ejecuta, solo muestra (apply/render)
  --channel NAME           Filtro para list
  --path PATH              Directorio base (por defecto: templates/)

Ejemplos:
  src/tools/templatectl.sh list --channel Stable
  src/tools/templatectl.sh validate templates/
  src/tools/templatectl.sh render templates/windows/windows-gaming.yaml --vmid 200 --storage-pool local-lvm
  sudo src/tools/templatectl.sh apply templates/linux/linux-workstation.yaml --vmid 210 --storage-pool auto
EOF
}

validate_vmid_arg() {
  local vmid="$1"
  [[ "$vmid" =~ ^[0-9]+$ ]] || die "--vmid debe ser numerico"
  (( vmid >= 100 && vmid <= 999999999 )) || die "--vmid debe estar entre 100 y 999999999"
}

validate_storage_pool_arg() {
  local pool="$1"
  [[ -z "$pool" ]] && return 0
  [[ "$pool" == "auto" || "$pool" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] \
    || die "--storage-pool contiene caracteres no soportados"
}

validate_disk_size_arg() {
  local size="$1"
  [[ -z "$size" ]] && return 0
  [[ "$size" =~ ^[0-9]+$ ]] || die "--disk-size debe ser numerico"
  (( size >= 8 && size <= 65536 )) || die "--disk-size debe estar entre 8 y 65536 GiB"
}

parse_render_apply_args() {
  local -n out_vmid=$1
  local -n out_pool=$2
  local -n out_disk=$3
  local -n out_dry=$4
  local -n out_no_template=$5
  shift 5

  out_vmid=""
  out_pool=""
  out_disk=""
  out_dry="false"
  out_no_template="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vmid)
        out_vmid="${2:-}"
        shift 2
        ;;
      --storage-pool)
        out_pool="${2:-}"
        shift 2
        ;;
      --disk-size)
        out_disk="${2:-}"
        shift 2
        ;;
      --dry-run)
        out_dry="true"
        shift
        ;;
      --no-convert-template)
        out_no_template="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Flag desconocido: $1"
        ;;
    esac
  done

  [[ -n "$out_vmid" ]] || die "--vmid es obligatorio"
  validate_vmid_arg "$out_vmid"
  validate_storage_pool_arg "$out_pool"
  validate_disk_size_arg "$out_disk"
}

cmd_list() {
  local channel=""
  local base="templates"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --channel)
        channel="${2:-}"
        shift 2
        ;;
      --path)
        base="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Flag desconocido para list: $1"
        ;;
    esac
  done

  require_tools python3
  [[ -d "$base" ]] || die "No existe el directorio: $base"

  python3 - "$base" "$channel" <<'PY'
import os
import sys

try:
    import yaml
except Exception as exc:
    print(f"ERROR: falta Python module PyYAML: {exc}", file=sys.stderr)
    sys.exit(1)

base, channel = sys.argv[1], sys.argv[2]
rows = []
for root, _, files in os.walk(base):
    for name in sorted(files):
        if not name.endswith(".yaml"):
            continue
        path = os.path.join(root, name)
        with open(path, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
        meta = data.get("metadata", {})
        spec = data.get("spec", {})
        vm = spec.get("vm", {})
        ch = meta.get("channel", "")
        if channel and ch != channel:
            continue
        rows.append((meta.get("name", ""), ch, meta.get("version", ""), vm.get("ostype", ""), path))

print(f"{'TEMPLATE':<28} {'CHANNEL':<12} {'VERSION':<12} {'OSTYPE':<10} PATH")
print(f"{'--------':<28} {'-------':<12} {'-------':<12} {'------':<10} ----")
for row in rows:
    print(f"{row[0]:<28} {row[1]:<12} {row[2]:<12} {row[3]:<10} {row[4]}")
PY
}

cmd_validate() {
  local target="${1:-}"
  [[ -n "$target" ]] || die "Uso: validate <path|file>"
  require_tools python3
  [[ -f "$SCHEMA_PATH" ]] || die "No se encuentra el schema: $SCHEMA_PATH"

  python3 - "$SCHEMA_PATH" "$target" <<'PY'
import glob
import json
import os
import sys

try:
    import yaml
    from jsonschema import Draft202012Validator
except Exception as exc:
    print(f"ERROR: faltan modulos Python requeridos (PyYAML/jsonschema): {exc}", file=sys.stderr)
    sys.exit(1)

schema_path, target = sys.argv[1], sys.argv[2]
with open(schema_path, "r", encoding="utf-8") as fh:
    schema = json.load(fh)

validator = Draft202012Validator(schema)

if os.path.isdir(target):
    files = sorted(glob.glob(os.path.join(target, "**", "*.yaml"), recursive=True))
elif os.path.isfile(target):
    files = [target]
else:
    print(f"Ruta no valida: {target}", file=sys.stderr)
    sys.exit(1)

failed = False
for path in files:
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    errors = sorted(validator.iter_errors(data), key=lambda e: list(e.absolute_path))
    if errors:
        failed = True
        print(f"FAIL {path}", file=sys.stderr)
        for error in errors:
            where = ".".join(str(p) for p in error.absolute_path) or "<root>"
            print(f"  - {where}: {error.message}", file=sys.stderr)
    else:
        print(f"OK {path}")

sys.exit(1 if failed else 0)
PY
}

render_args_array() {
  local file="$1"
  local vmid="$2"
  local pool="$3"
  local disk="$4"
  local format="$5"

  local argv=("$RENDERER" --file "$file" --vmid "$vmid" --format "$format")
  [[ -n "$pool" ]] && argv+=(--storage-pool "$pool")
  [[ -n "$disk" ]] && argv+=(--disk-size "$disk")
  "${argv[@]}"
}

cmd_render() {
  local file="${1:-}"
  shift || true
  [[ -f "$file" ]] || die "Fichero YAML no encontrado: $file"
  [[ -x "$RENDERER" ]] || die "Renderer no ejecutable: $RENDERER"

  local vmid pool disk dry no_template
  parse_render_apply_args vmid pool disk dry no_template "$@"

  render_args_array "$file" "$vmid" "$pool" "$disk" human
}

cmd_apply() {
  local file="${1:-}"
  shift || true
  [[ -f "$file" ]] || die "Fichero YAML no encontrado: $file"
  [[ -x "$RENDERER" ]] || die "Renderer no ejecutable: $RENDERER"

  local vmid pool disk dry no_template
  parse_render_apply_args vmid pool disk dry no_template "$@"

  local plan_file
  plan_file="$(mktemp "${TMPDIR:-/tmp}/pecu-template-plan.XXXXXX.json")"

  if ! render_args_array "$file" "$vmid" "$pool" "$disk" json > "$plan_file"; then
    rm -f "$plan_file"
    return 1
  fi

  if [[ "$dry" != "true" ]]; then
    require_tools qm
  fi

  local rc=0
  python3 - "$plan_file" "$dry" "$no_template" "$vmid" <<'PY' || rc=$?
import json
import shlex
import shutil
import subprocess
import sys

plan_path, dry, no_template, vmid = sys.argv[1:5]
with open(plan_path, "r", encoding="utf-8") as fh:
    plan = json.load(fh)

commands = plan.get("commands", [])
if no_template != "true":
    commands.append({"argv": ["qm", "template", vmid], "description": "convert to template"})

def validate_argv(argv):
    if not isinstance(argv, list) or not argv:
        raise SystemExit("ERROR: comando JSON sin argv valido")
    if argv[0] != "qm":
        raise SystemExit(f"ERROR: comando no permitido: {argv[0]!r}")
    if any(not isinstance(item, str) or item == "" for item in argv):
        raise SystemExit("ERROR: argv contiene argumentos invalidos")

if dry == "true":
    for command in commands:
        desc = command.get("description")
        if desc:
            print(f"# {desc}")
        validate_argv(command.get("argv"))
        print(shlex.join(command["argv"]))
    print("# [dry-run] No se ejecuto ningun comando.")
    sys.exit(0)

if shutil.which("qm") is None:
    raise SystemExit("ERROR: falta herramienta: qm")

print(f"# Ejecutando {len(commands)} comando(s) qm")
for command in commands:
    argv = command.get("argv")
    validate_argv(argv)
    print("+ " + shlex.join(argv), flush=True)
    subprocess.run(argv, check=True)

print(f"# Listo. VMID {vmid} configurada.")
PY
  rm -f "$plan_file"
  return "$rc"
}

main() {
  [[ $# -gt 0 ]] || {
    usage
    exit 1
  }

  local cmd="$1"
  shift || true

  case "$cmd" in
    list)
      cmd_list "$@"
      ;;
    validate)
      cmd_validate "$@"
      ;;
    render)
      cmd_render "$@"
      ;;
    apply)
      cmd_apply "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      die "Comando desconocido: $cmd"
      ;;
  esac
}

main "$@"
