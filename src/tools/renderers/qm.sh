#!/usr/bin/env bash
set -euo pipefail

# qm.sh — traduce un YAML de plantilla P  local efi_size efi_prek tmp_size tmp_ver
  efi_size="$(yget "$file" '.spec.storage.efi.sizeGiB // 0')"
  efi_prek="$(yget "$file" '.spec.storage.efi.preEnrolledKeys // false')"
  tmp_size="$(yget "$file" '.spec.storage.tpm.sizeGiB // 0')"
  tmp_ver="$(yget "$file" '.spec.storage.tpm.version // ""')" una serie de comandos 'qm'
# No ejecuta nada: escribe a STDOUT una lista de comandos, uno por línea.
# Flags:
#   --file <path.yaml> (obligatorio)
#   --vmid <id>        (obligatorio)
#   --storage-pool <auto|local-lvm|local>  (opcional; sobreescribe YAML)
#   --disk-size <GiB>  (opcional; sobreescribe tamaño de bootdisk)
#   --dry-run          (ignorado aquí; el renderer siempre es no-ejecutable)

have() { command -v "$1" >/dev/null 2>&1; }

die() { echo "ERROR: $*" >&2; exit 1; }

yget() { yq eval "$2" "$1"; }

detect_pool() {
  # Detección simple: si existe 'local-lvm' con content images, usarlo; si no, 'local'.
  if have pvesm; then
    if pvesm status | awk '{print $1,$5}' | grep -qE '^local-lvm .*images'; then
      echo "local-lvm"; return
    fi
    if pvesm status | awk '{print $1,$5}' | grep -qE '^local .*images'; then
      echo "local"; return
    fi
  fi
  # Fallback conservador
  echo "local-lvm"
}

ensure_tools() {
  for t in yq jq awk sed; do
    command -v "$t" >/dev/null 2>&1 || die "Falta herramienta: $t"
  done
}

main() {
  ensure_tools

  local file="" vmid="" pool_override="" disk_override="" dry="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="${2:-}"; shift 2;;
      --vmid) vmid="${2:-}"; shift 2;;
      --storage-pool) pool_override="${2:-}"; shift 2;;
      --disk-size) disk_override="${2:-}"; shift 2;;
      --dry-run) dry="true"; shift 1;;
      *) die "Flag desconocido: $1";;
    esac
  done
  [[ -f "$file" ]] || die "No existe YAML: $file"
  [[ -n "$vmid" ]] || die "--vmid obligatorio"

  # Extrae campos
  local name ostype cpu sockets cores mem bios chipset tablet args
  name="$(yget "$file" '.spec.vm.name // .metadata.name')"
  ostype="$(yget "$file" '.spec.vm.ostype')"
  cpu="$(yget "$file" '.spec.vm.cpu')"
  sockets="$(yget "$file" '.spec.vm.sockets')"
  cores="$(yget "$file" '.spec.vm.cores')"
  mem="$(yget "$file" '.spec.vm.memoryMiB')"
  bios="$(yget "$file" '.spec.vm.bios')"
  chipset="$(yget "$file" '.spec.vm.chipset')"
  tablet="$(yget "$file" '.spec.vm.tablet // false')"
  args="$(yget "$file" '.spec.vm.args // ""')"

  local pool yaml_pool bus size format
  yaml_pool="$(yget "$file" '.spec.storage.pool')"
  pool="$yaml_pool"
  [[ -n "$pool_override" ]] && pool="$pool_override"
  [[ "$pool" == "auto" || -z "$pool" ]] && pool="$(detect_pool)"

  bus="$(yget "$file" '.spec.storage.bootdisk.bus')"
  size="$(yget "$file" '.spec.storage.bootdisk.sizeGiB')"
  format="$(yget "$file" '.spec.storage.bootdisk.format // "raw"')"
  [[ -n "$disk_override" ]] && size="$disk_override"

  local efi_size efi_prek tpm_size tmp_ver
  efi_size="$(yget "$file" '.spec.storage.efi.sizeGiB // 0')"
  efi_prek="$(yget "$file" '.spec.storage.efi.preEnrolledKeys // false')"
  tmp_size="$(yget "$file" '.spec.storage.tmp.sizeGiB // 0')"
  tmp_ver="$(yget "$file" '.spec.storage.tmp.version // ""')"

  local nic_count nic_model nic_bridge nic_fw
  nic_count="$(yq eval '.spec.network | length' "$file")"

  local allow_machine add_usb
  allow_machine="$(yget "$file" '.spec.policy.allowMachinePin')"
  add_usb="$(yget "$file" '.spec.policy.addUsbRootHub')"

  # Build qm create command as string
  local create_cmd="qm create ${vmid}"
  create_cmd+=" --name ${name}"
  create_cmd+=" --ostype ${ostype}"
  create_cmd+=" --cpu '${cpu}'"
  create_cmd+=" --sockets ${sockets}"
  create_cmd+=" --cores ${cores}"
  create_cmd+=" --memory ${mem}"
  create_cmd+=" --scsihw virtio-scsi-single"

  if [[ "$bios" == "ovmf" ]]; then
    create_cmd+=" --bios ovmf"
    # UEFI requiere máquina Q35 habitualmente, pero NO fijamos --machine si policy no lo permite
  else
    create_cmd+=" --bios seabios"
  fi

  if [[ "${tablet}" == "true" ]]; then
    create_cmd+=" --tablet 1"
  else
    create_cmd+=" --tablet 0"
  fi

  if [[ -n "$args" && "$args" != "null" ]]; then
    create_cmd+=" --args \"$args\""
  fi

  # Discos: bootdisk
  # En local-lvm: 'pool:size' sin format
  # En local (directory): usamos format si es raw o qcow2
  local disk_arg=""
  case "$pool" in
    local-lvm)
      disk_arg="${pool}:${size}"
      ;;
    local)
      # Para directory storage permitimos format=raw/qcow2
      disk_arg="${pool}:${size},format=${format}"
      ;;
    *)
      # Para otros storages (si existen), usamos la sintaxis simple
      disk_arg="${pool}:${size}"
      ;;
  esac

  # Mapea bus → <bus>0
  local bootdisk="${bus}0"
  create_cmd+=" --${bootdisk} ${disk_arg}"
  create_cmd+=" --bootdisk ${bus}"

  # NICs
  # Añadimos en create para la primera NIC; siguientes con qm set
  if (( nic_count > 0 )); then
    nic_model="$(yq eval '.spec.network[0].model' "$file")"
    nic_bridge="$(yq eval '.spec.network[0].bridge' "$file")"
    nic_fw="$(yq eval '.spec.network[0].firewall // false' "$file")"
    local net0="model=${nic_model},bridge=${nic_bridge}"
    [[ "$nic_fw" == "true" ]] && net0="${net0},firewall=1"
    create_cmd+=" --net0 ${net0}"
  fi

  # Output the main create command
  echo "$create_cmd"

  # 4) NICs adicionales (net1, net2…)
  if (( nic_count > 1 )); then
    for i in $(seq 1 $((nic_count-1))); do
      nic_model="$(yq eval ".spec.network[$i].model" "$file")"
      nic_bridge="$(yq eval ".spec.network[$i].bridge" "$file")"
      nic_fw="$(yq eval ".spec.network[$i].firewall // false" "$file")"
      local neti="model=${nic_model},bridge=${nic_bridge}"
      [[ "$nic_fw" == "true" ]] && neti="${neti},firewall=1"
      echo "qm set ${vmid} --net${i} ${neti}"
    done
  fi

  # 5) EFI / TPM (si proceden)
  if [[ "$bios" == "ovmf" && "$efi_size" != "0" ]]; then
    local efidisk="${pool}:${efi_size}"
    # pre-enrolled-keys=1 si procede
    if [[ "$efi_prek" == "true" ]]; then
      efidisk="${efidisk},pre-enrolled-keys=1"
    fi
    echo "qm set ${vmid} --efidisk0 ${efidisk}"
  fi

  if [[ "$tmp_size" != "0" && -n "$tmp_ver" ]]; then
    local tpmarg="${pool}:${tmp_size},version=${tmp_ver}"
    echo "qm set ${vmid} --tpmstate0 ${tpmarg}"
  fi

  # 6) Política: machine pin / usb root hub (por defecto NO)
  if [[ "$allow_machine" != "true" ]]; then
    # No hacemos nada: evitamos --machine fijo
    :
  fi
  if [[ "$add_usb" == "true" ]]; then
    # Si el usuario lo forzara explícitamente (no recomendado)
    echo "qm set ${vmid} --usb0 host=1d6b:0002"
  fi
}

main "$@"
