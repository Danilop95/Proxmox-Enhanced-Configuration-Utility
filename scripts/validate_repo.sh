#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
skips=0

log() {
  printf '%s\n' "$*"
}

ok() {
  log "OK   $*"
}

warn() {
  log "WARN $*"
}

fail() {
  log "FAIL $*"
  failures=$((failures + 1))
}

skip() {
  log "SKIP $*"
  skips=$((skips + 1))
}

have() {
  command -v "$1" >/dev/null 2>&1
}

strict_deps=false
if [[ "${CI:-}" == "true" || "${PECU_VALIDATE_STRICT_DEPS:-}" == "true" ]]; then
  strict_deps=true
fi

cd "$ROOT_DIR"

scripts=(
  "src/proxmox-configurator.sh"
  "scripts/pecu_release_selector.sh"
  "src/tools/templatectl.sh"
  "src/tools/renderers/qm.sh"
)

log "== Bash syntax =="
for script in "${scripts[@]}"; do
  if bash -n "$script"; then
    ok "bash -n $script"
  else
    fail "bash -n $script"
  fi
done

log
log "== ShellCheck =="
if have shellcheck; then
  if shellcheck -x -S error "${scripts[@]}"; then
    ok "shellcheck -S error ${scripts[*]}"
  else
    fail "shellcheck reported error-severity issues"
  fi
else
  if $strict_deps; then
    fail "shellcheck no esta instalado"
  else
    skip "shellcheck no esta instalado; en CI se instala antes de ejecutar este script"
  fi
fi

log
log "== YAML lint =="
if have yamllint; then
  if yamllint templates .github/workflows; then
    ok "yamllint templates .github/workflows"
  else
    fail "yamllint reported issues"
  fi
else
  if $strict_deps; then
    fail "yamllint no esta instalado"
  else
    skip "yamllint no esta instalado; en CI se instala antes de ejecutar este script"
  fi
fi

log
log "== Python modules =="
if python3 - <<'PY'
import jsonschema
import yaml
PY
then
  ok "Python modules jsonschema and PyYAML"
else
  fail "faltan modulos Python requeridos: jsonschema y/o PyYAML"
fi

log
log "== Template schema validation =="
if src/tools/templatectl.sh validate templates/; then
  ok "templates validate against schema"
else
  fail "template schema validation failed"
fi

log
log "== Renderer dry-run checks =="
mapfile -t templates < <(find templates -type f -name '*.yaml' | sort)
vmid=9000
for template in "${templates[@]}"; do
  output=""
  if output="$(src/tools/templatectl.sh render "$template" --vmid "$vmid" --storage-pool local-lvm --dry-run 2>&1)"; then
    ok "render $template"
  else
    printf '%s\n' "$output"
    fail "render $template"
    vmid=$((vmid + 1))
    continue
  fi

  if grep -qE -- '--bootdisk[[:space:]]+(scsi|virtio|sata|ide)([[:space:]]|$)' <<<"$output"; then
    fail "$template renders legacy bootdisk bus instead of concrete disk"
  fi

  if grep -q -- '^[[:space:]]*tpm:' "$template"; then
    if grep -q -- '--tpmstate0' <<<"$output"; then
      ok "TPM renders for $template"
    else
      fail "$template declares storage.tpm but render has no --tpmstate0"
    fi
  fi

  if grep -q -- 'chipset: q35' "$template"; then
    if grep -q -- '--machine q35' <<<"$output"; then
      ok "q35 renders for $template"
    elif grep -q -- 'allowMachinePin=false' <<<"$output"; then
      ok "q35 omission documented for $template"
    else
      fail "$template declares q35 but render neither applies nor documents it"
    fi
  fi

  if output="$(src/tools/templatectl.sh apply "$template" --vmid "$vmid" --storage-pool local-lvm --dry-run 2>&1)"; then
    ok "apply --dry-run $template"
  else
    printf '%s\n' "$output"
    fail "apply --dry-run $template"
  fi

  vmid=$((vmid + 1))
done

log
log "== Renderer rejection checks =="
tmp_template="$(mktemp "${TMPDIR:-/tmp}/pecu-bad-template.XXXXXX.yaml")"
cat > "$tmp_template" <<'YAML'
apiVersion: pecu.io/v1
kind: VMTemplate
metadata:
  name: bad-unsafe-args
  version: "2026.05.11"
  channel: Experimental
spec:
  vm:
    ostype: l26
    name: bad-unsafe-args
    cpu: host
    sockets: 1
    cores: 1
    memoryMiB: 1024
    chipset: q35
    bios: ovmf
    args: "-cpu host"
  storage:
    pool: local-lvm
    bootdisk:
      bus: scsi
      sizeGiB: 8
      format: raw
  network:
    - model: virtio
      bridge: vmbr0
      firewall: false
  policy:
    allowMachinePin: true
    addUsbRootHub: false
    allowUnsafeArgs: "false"
YAML

if src/tools/templatectl.sh render "$tmp_template" --vmid 9100 --storage-pool local-lvm >/dev/null 2>&1; then
  fail "renderer accepted non-boolean allowUnsafeArgs with raw args"
else
  ok "renderer rejects non-boolean allowUnsafeArgs with raw args"
fi
rm -f "$tmp_template"

log
log "== Unsafe execution guard =="
if grep -RInE '^[[:space:]]*eval([[:space:]]|$)' src scripts --include='*.sh'; then
  fail "eval command found in executable shell scripts"
else
  ok "no eval command in executable shell scripts"
fi

log
if (( failures > 0 )); then
  log "Validation failed: $failures failure(s), $skips skipped check(s)."
  exit 1
fi

log "Validation passed: $skips skipped check(s)."
