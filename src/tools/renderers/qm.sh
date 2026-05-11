#!/usr/bin/env bash
set -euo pipefail

# qm.sh - renderiza una plantilla PECU como comandos qm seguros.
#
# Este renderer no ejecuta nada. Puede emitir:
#   --format human  comandos shell-quoted para lectura/dry-run
#   --format json   JSON estructurado con arrays argv para ejecucion segura

die() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || die "Falta herramienta: python3"

python3 - "$@" <<'PY'
import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

try:
    import yaml
except Exception as exc:
    print(f"ERROR: falta Python module PyYAML: {exc}", file=sys.stderr)
    sys.exit(1)


VMID_RE = re.compile(r"^[0-9]+$")
VM_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]{0,62}$")
STORAGE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
BRIDGE_RE = re.compile(r"^vmbr[0-9]{1,4}$")
CPU_RE = re.compile(r"^[A-Za-z0-9_.+-]+(,[A-Za-z0-9_.+-]+(=[A-Za-z0-9_.:+-]+)?)*$")
ARGS_RE = re.compile(r"^[A-Za-z0-9_.,=:+\-/ ]{1,512}$")
INT_RE = re.compile(r"^[0-9]+$")

OSTYPES = {
    "l24", "l26", "solaris", "other",
    "win7", "win8", "win10", "win11", "w2k", "w2k3", "w2k8", "wvista", "wxp",
}

BUS_TYPES = {"scsi", "virtio", "sata", "ide"}
DISK_FORMATS = {"raw", "qcow2"}
NIC_MODELS = {"virtio", "e1000", "vmxnet3", "rtl8139"}


def die(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def warn(warnings, message):
    warnings.append(message)
    print(f"WARN: {message}", file=sys.stderr)


def load_template(path):
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    if not isinstance(data, dict):
        die(f"Plantilla vacia o invalida: {path}")
    return data


def get(mapping, dotted, default=None):
    cur = mapping
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur


def parse_int(value, field, minimum=None, maximum=None):
    if isinstance(value, bool):
        die(f"{field} debe ser numerico")
    if isinstance(value, int):
        num = value
    elif isinstance(value, str) and INT_RE.match(value):
        num = int(value)
    else:
        die(f"{field} debe ser numerico")

    if minimum is not None and num < minimum:
        die(f"{field} debe ser >= {minimum}")
    if maximum is not None and num > maximum:
        die(f"{field} debe ser <= {maximum}")
    return num


def parse_bool(value, field, default=None):
    if value is None:
        if default is None:
            die(f"{field} debe ser booleano")
        return default
    if not isinstance(value, bool):
        die(f"{field} debe ser booleano")
    return value


def validate_vmid(value):
    if not isinstance(value, str) or not VMID_RE.fullmatch(value):
        die("--vmid debe ser numerico")
    vmid = int(value)
    if vmid < 100 or vmid > 999999999:
        die("--vmid debe estar entre 100 y 999999999")
    return str(vmid)


def validate_regex(value, regex, field):
    if not isinstance(value, str) or not regex.fullmatch(value):
        die(f"{field} tiene formato inseguro o no soportado: {value!r}")
    return value


def detect_pool(warnings):
    pvesm = shutil.which("pvesm")
    if not pvesm:
        warn(warnings, "pvesm no esta disponible; usando fallback local-lvm para render no-Proxmox")
        return "local-lvm"

    try:
        proc = subprocess.run(
            [pvesm, "status", "--content", "images"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        warn(warnings, "no se pudo ejecutar pvesm; usando fallback local-lvm")
        return "local-lvm"

    if proc.returncode != 0:
        warn(warnings, "pvesm status fallo; usando fallback local-lvm")
        return "local-lvm"

    storage_names = []
    for line in proc.stdout.splitlines()[1:]:
        parts = line.split()
        if not parts:
            continue
        storage_names.append(parts[0])

    if "local-lvm" in storage_names:
        return "local-lvm"
    if "local" in storage_names:
        return "local"

    warn(warnings, "no se encontro storage images local/local-lvm; usando fallback local-lvm")
    return "local-lvm"


def disk_volume_arg(pool, size_gib, disk_format):
    if pool == "local":
        return f"{pool}:{size_gib},format={disk_format}"
    return f"{pool}:{size_gib}"


def efi_volume_arg(pool, size_gib, disk_format, pre_enrolled_keys):
    parts = [f"{pool}:{size_gib}"]
    if pool == "local":
        parts.append(f"format={disk_format}")
    parts.append("efitype=4m")
    parts.append(f"pre-enrolled-keys={1 if pre_enrolled_keys else 0}")
    return ",".join(parts)


def tpm_volume_arg(pool, size_gib, version):
    return f"{pool}:{size_gib},version={version}"


def net_arg(nic):
    model = validate_regex(nic.get("model"), re.compile(r"^(virtio|e1000|vmxnet3|rtl8139)$"), "network.model")
    bridge = validate_regex(nic.get("bridge"), BRIDGE_RE, "network.bridge")
    arg = f"{model},bridge={bridge}"
    if parse_bool(nic.get("firewall"), "network.firewall", default=False):
        arg += ",firewall=1"
    return arg


def build_commands(data, args):
    warnings = []
    vmid = validate_vmid(args.vmid)

    metadata_name = get(data, "metadata.name")
    vm = get(data, "spec.vm", {})
    storage = get(data, "spec.storage", {})
    policy = get(data, "spec.policy", {})
    network = get(data, "spec.network", [])

    if not isinstance(vm, dict) or not isinstance(storage, dict):
        die("spec.vm y spec.storage son obligatorios")
    if not isinstance(policy, dict):
        die("spec.policy es obligatorio")
    if not isinstance(network, list) or not network:
        die("spec.network debe contener al menos una NIC")

    name = vm.get("name") or metadata_name
    validate_regex(name, VM_NAME_RE, "spec.vm.name")

    ostype = vm.get("ostype")
    if ostype not in OSTYPES:
        die(f"spec.vm.ostype no soportado: {ostype!r}")

    cpu = validate_regex(vm.get("cpu"), CPU_RE, "spec.vm.cpu")
    sockets = parse_int(vm.get("sockets"), "spec.vm.sockets", 1, 8)
    cores = parse_int(vm.get("cores"), "spec.vm.cores", 1, 512)
    memory = parse_int(vm.get("memoryMiB"), "spec.vm.memoryMiB", 256, 1048576)

    bios = vm.get("bios")
    if bios not in {"ovmf", "seabios"}:
        die(f"spec.vm.bios no soportado: {bios!r}")

    chipset = vm.get("chipset", "auto")
    if chipset not in {"q35", "i440fx", "auto"}:
        die(f"spec.vm.chipset no soportado: {chipset!r}")

    allow_machine_pin = parse_bool(policy.get("allowMachinePin"), "spec.policy.allowMachinePin")
    add_usb_root_hub = parse_bool(policy.get("addUsbRootHub"), "spec.policy.addUsbRootHub")
    allow_unsafe_args = parse_bool(policy.get("allowUnsafeArgs"), "spec.policy.allowUnsafeArgs")

    raw_args = vm.get("args")
    if raw_args in (None, "", "null"):
        raw_args = ""
    elif not allow_unsafe_args:
        die("spec.vm.args requiere spec.policy.allowUnsafeArgs: true")
    else:
        validate_regex(raw_args, ARGS_RE, "spec.vm.args")

    yaml_pool = storage.get("pool", "auto")
    if args.storage_pool:
        pool = args.storage_pool
    else:
        pool = yaml_pool
    if not isinstance(pool, str):
        die("spec.storage.pool debe ser string")
    if pool == "auto":
        pool = detect_pool(warnings)
    validate_regex(pool, STORAGE_RE, "storage pool")

    bootdisk = storage.get("bootdisk", {})
    if not isinstance(bootdisk, dict):
        die("spec.storage.bootdisk es obligatorio")

    bus = bootdisk.get("bus")
    if bus not in BUS_TYPES:
        die(f"spec.storage.bootdisk.bus no soportado: {bus!r}")
    disk_name = f"{bus}0"

    size_value = args.disk_size if args.disk_size else bootdisk.get("sizeGiB")
    size_gib = parse_int(size_value, "boot disk size", 8, 65536)
    disk_format = bootdisk.get("format", "raw")
    if disk_format not in DISK_FORMATS:
        die(f"spec.storage.bootdisk.format no soportado: {disk_format!r}")

    tablet = "1" if parse_bool(vm.get("tablet"), "spec.vm.tablet", default=False) else "0"

    create = [
        "qm", "create", vmid,
        "--name", name,
        "--ostype", ostype,
        "--cpu", cpu,
        "--sockets", str(sockets),
        "--cores", str(cores),
        "--memory", str(memory),
        "--scsihw", "virtio-scsi-single",
        "--bios", bios,
        "--tablet", tablet,
    ]

    if chipset != "auto":
        if allow_machine_pin:
            machine = "q35" if chipset == "q35" else "pc"
            create.extend(["--machine", machine])
        else:
            warn(
                warnings,
                f"spec.vm.chipset={chipset} no se aplica porque allowMachinePin=false",
            )

    if raw_args:
        create.extend(["--args", raw_args])

    create.extend([f"--{disk_name}", disk_volume_arg(pool, size_gib, disk_format)])
    create.extend(["--bootdisk", disk_name])
    create.extend(["--net0", net_arg(network[0])])

    commands = [{"argv": create, "description": "create VM"}]

    for idx, nic in enumerate(network[1:], start=1):
        commands.append(
            {
                "argv": ["qm", "set", vmid, f"--net{idx}", net_arg(nic)],
                "description": f"set net{idx}",
            }
        )

    efi = storage.get("efi")
    if bios == "ovmf" and isinstance(efi, dict):
        efi_size = parse_int(efi.get("sizeGiB", 0), "spec.storage.efi.sizeGiB", 0, 64)
        if efi_size > 0:
            efi_prek = parse_bool(efi.get("preEnrolledKeys"), "spec.storage.efi.preEnrolledKeys", default=False)
            commands.append(
                {
                    "argv": [
                        "qm", "set", vmid,
                        "--efidisk0",
                        efi_volume_arg(pool, efi_size, disk_format, efi_prek),
                    ],
                    "description": "set UEFI disk",
                }
            )
    elif bios == "ovmf":
        warn(warnings, "bios=ovmf sin spec.storage.efi; Proxmox puede crear una VM UEFI incompleta")

    tpm = storage.get("tpm")
    if isinstance(tpm, dict):
        tpm_size = parse_int(tpm.get("sizeGiB", 0), "spec.storage.tpm.sizeGiB", 0, 64)
        tpm_version = tpm.get("version")
        if tpm_size > 0:
            if tpm_version != "v2.0":
                die("spec.storage.tpm.version debe ser v2.0")
            commands.append(
                {
                    "argv": [
                        "qm", "set", vmid,
                        "--tpmstate0",
                        tpm_volume_arg(pool, tpm_size, tpm_version),
                    ],
                    "description": "set TPM state",
                }
            )

    if add_usb_root_hub:
        commands.append(
            {
                "argv": ["qm", "set", vmid, "--usb0", "host=1d6b:0002"],
                "description": "set USB root hub",
            }
        )

    return {"commands": commands, "warnings": warnings}


def emit_human(result):
    for message in result["warnings"]:
        print(f"# WARNING: {message}")
    for command in result["commands"]:
        desc = command.get("description")
        if desc:
            print(f"# {desc}")
        print(shlex.join(command["argv"]))


def main():
    parser = argparse.ArgumentParser(description="PECU qm renderer")
    parser.add_argument("--file", required=True)
    parser.add_argument("--vmid", required=True)
    parser.add_argument("--storage-pool", default="")
    parser.add_argument("--disk-size", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--format", choices=["human", "json"], default="human")
    parsed = parser.parse_args()

    if not os.path.isfile(parsed.file):
        die(f"No existe YAML: {parsed.file}")

    data = load_template(parsed.file)
    result = build_commands(data, parsed)

    if parsed.format == "json":
        json.dump(result, sys.stdout, separators=(",", ":"))
        print()
    else:
        emit_human(result)


if __name__ == "__main__":
    main()
PY
