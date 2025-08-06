#!/usr/bin/env bash
set -euo pipefail

# templatectl.sh — CLI para listar, validar, renderizar y aplicar plantillas PECU
# Requisitos: bash, jq, yq (v4), python3 (jsonschema, pyyaml), find, grep, awk
# Uso: templatectl.sh <list|validate|render|apply> [args]
# Ejemplos:
#   templatectl.sh list --channel Stable
#   templatectl.sh validate templates/
#   templatectl.sh render templates/windows/windows-gaming.yaml --vmid 200 --storage-pool local-lvm --dry-run
#   sudo templatectl.sh apply templates/windows/windows-gaming.yaml --vmid 200 --storage-pool local-lvm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCHEMA_PATH="${REPO_ROOT}/templates/schemas/template.schema.json"
RENDERER="${SCRIPT_DIR}/renderers/qm.sh"

die() { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

require_tools() {
  local missing=()
  for t in "$@"; do have "$t" || missing+=("$t"); done
  if (( ${#missing[@]} )); then
    die "Faltan herramientas: ${missing[*]}"
  fi
}

usage() {
  cat <<'EOF'
templatectl.sh — gestiona VM templates (PECU)

Comandos:
  list [--channel <Stable|Beta|Experimental>] [--path <dir>]
  validate <path|file>
  render <file.yaml> --vmid <id> [--storage-pool <auto|local-lvm|local>] [--disk-size <GiB>] [--dry-run]
  apply  <file.yaml> --vmid <id> [--storage-pool <auto|local-lvm|local>] [--disk-size <GiB>] [--no-convert-template] [--dry-run]

Flags comunes:
  --vmid N                 VMID obligatorio para render/apply
  --storage-pool NAME      Fuerza pool (por defecto: valor de YAML o 'auto')
  --disk-size GiB          Sobrescribe tamaño de disco de arranque
  --dry-run                No ejecuta, solo muestra (en apply/render)
  --channel NAME           Filtro para 'list'
  --path PATH              Directorio base (por defecto: templates/)

Ejemplos:
  templatectl.sh list --channel Stable
  templatectl.sh validate templates/
  templatectl.sh render templates/windows/windows-gaming.yaml --vmid 200 --storage-pool local-lvm --dry-run
  sudo templatectl.sh apply templates/linux/linux-workstation.yaml --vmid 210 --storage-pool auto
EOF
}

yaml_get() {
  local file="$1" q="$2"
  yq eval -r "$q" "$file"
}

cmd_list() {
  local channel="" base="templates"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --channel) channel="${2:-}"; shift 2;;
      --path)    base="${2:-}"; shift 2;;
      -h|--help) usage; exit 0;;
      *) die "Flag desconocido para list: $1";;
    esac
  done

  require_tools yq jq find

  [[ -d "$base" ]] || die "No existe el directorio: $base"
  mapfile -d '' files < <(find "$base" -type f -name '*.yaml' -print0)

  printf "%-28s %-12s %-10s %-10s %s\n" "TEMPLATE" "CHANNEL" "VERSION" "OSTYPE" "PATH"
  printf "%-28s %-12s %-10s %-10s %s\n" "--------" "-------" "-------" "------" "----"
  for f in "${files[@]}"; do
    local ch ver name ost
    ch="$(yaml_get "$f" '.metadata.channel')" || true
    ver="$(yaml_get "$f" '.metadata.version')" || true
    name="$(yaml_get "$f" '.metadata.name')" || true
    ost="$(yaml_get "$f" '.spec.vm.ostype')" || true

    [[ -n "$channel" && "$ch" != "$channel" ]] && continue
    printf "%-28s %-12s %-10s %-10s %s\n" "$name" "$ch" "$ver" "$ost" "$f"
  done
}

cmd_validate() {
  local target="${1:-}"
  [[ -n "$target" ]] || die "Uso: validate <path|file>"
  require_tools python3 yq

  [[ -f "$SCHEMA_PATH" ]] || die "No se encuentra el schema: $SCHEMA_PATH"

  python3 - <<PY
import sys, json, glob, os, yaml
from jsonschema import Draft202012Validator as V

schema_path = "${SCHEMA_PATH}"
with open(schema_path, 'r') as f:
    schema = json.load(f)
validator = V(schema)

def validate_file(p):
    with open(p, 'r') as f:
        data = yaml.safe_load(f)
    validator.validate(data)
    print("OK", p)

arg = "${target}"
if os.path.isdir(arg):
    for p in glob.glob(os.path.join(arg, '**/*.yaml'), recursive=True):
        validate_file(p)
elif os.path.isfile(arg):
    validate_file(arg)
else:
    print(f"Ruta no válida: {arg}", file=sys.stderr)
    sys.exit(1)
PY
}

common_parse_render_apply() {
  local -n _vmid=$1 _pool=$2 _disk=$3 _dry=$4 _no_tmpl=$5
  _vmid=""; _pool=""; _disk=""; _dry="false"; _no_tmpl="false"
  while [[ $# -gt 0 ]]; do
    case "$6" in
      --vmid)                _vmid="${7:-}"; shift 2;;
      --storage-pool)        _pool="${7:-}"; shift 2;;
      --disk-size)           _disk="${7:-}"; shift 2;;
      --dry-run)             _dry="true"; shift 1;;
      --no-convert-template) _no_tmpl="true"; shift 1;;
      *) break;;
    esac
  done
}

cmd_render() {
  local file="${1:-}"; shift || true
  [[ -f "$file" ]] || die "Fichero YAML no encontrado: $file"
  require_tools yq jq

  local vmid pool disk dry no_tmpl
  common_parse_render_apply vmid pool disk dry no_tmpl "$@"

  [[ -n "$vmid" ]] || die "--vmid es obligatorio"
  [[ -x "$RENDERER" ]] || die "Renderer no ejecutable: $RENDERER"

  "$RENDERER" \
    --file "$file" \
    --vmid "$vmid" \
    ${pool:+--storage-pool "$pool"} \
    ${disk:+--disk-size "$disk"} \
    ${dry:+--dry-run}
}

cmd_apply() {
  local file="${1:-}"; shift || true
  [[ -f "$file" ]] || die "Fichero YAML no encontrado: $file"
  require_tools yq jq

  local vmid pool disk dry no_tmpl
  common_parse_render_apply vmid pool disk dry no_tmpl "$@"
  [[ -n "$vmid" ]] || die "--vmid es obligatorio"

  # En apply, necesitamos 'qm'
  require_tools qm pvesm

  # Generamos comandos
  mapfile -t cmds < <("$RENDERER" --file "$file" --vmid "$vmid" ${pool:+--storage-pool "$pool"} ${disk:+--disk-size "$disk"} )

  if [[ "${dry}" == "true" ]]; then
    printf "%s\n" "${cmds[@]}"
    echo "# [dry-run] No se ejecutó ningún comando."
    exit 0
  fi

  echo "# Ejecutando ${#cmds[@]} comando(s) qm …"
  for c in "${cmds[@]}"; do
    echo "+ $c"
    eval "$c"
  done

  if [[ "${no_tmpl}" == "false" ]]; then
    echo "+ qm template ${vmid}"
    qm template "${vmid}"
  fi

  echo "# Listo. VMID ${vmid} configurada."
}

main() {
  [[ $# -gt 0 ]] || { usage; exit 1; }
  local cmd="$1"; shift || true
  case "$cmd" in
    list)     cmd_list "$@";;
    validate) cmd_validate "$@";;
    render)   cmd_render "$@";;
    apply)    cmd_apply "$@";;
    -h|--help|help) usage;;
    *) die "Comando desconocido: $cmd";;
  esac
}

main "$@"
