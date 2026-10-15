#!/usr/bin/env python3
"""Build the config disk, or create/import a first-boot-safe standalone VM.
Run from terraform/. No passwords are passed to Terraform or command arguments.
"""
import argparse
import getpass
import ipaddress
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

GENERATED = Path(".generated")

def run(args, capture=False):
    result = subprocess.run(args, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None

def tf(tool, *args, capture=False):
    return run([tool, *args], capture=capture)

def output(tool, name):
    return json.loads(tf(tool, "output", "-json", name, capture=True))

def write_raw(path, text):
    with path.open("xb") as f:
        os.chmod(path, 0o600)
        f.write(text.encode("ascii"))
        f.write(b"\n" * (2 * 1024 * 1024))
        f.truncate(1024 ** 3)

def yaml_config(network, hostname, domain, ntp, password, interface):
    # JSON-quoted scalars are valid YAML and safely escape punctuation.
    q = lambda value: json.dumps(value, ensure_ascii=True)
    address = str(ipaddress.IPv4Address(network["ip"]))
    prefix = int(network["prefix"])
    if not 0 <= prefix <= 32:
        raise ValueError("Invalid IPv4 prefix")
    gateway = str(ipaddress.IPv4Address(network["gateway"]))
    if not network["dns"]:
        raise ValueError("Network has no DNS servers")
    dns = "\n".join("    - " + q(str(ipaddress.ip_address(ip))) for ip in network["dns"])
    return (
        "cluster:\n"
        "  password: " + q(password) + "\n"
        "  domainname: " + q(domain) + "\n"
        "  dns_servers:\n" + dns + "\n"
        "  gateway:\n    ipv4_default: " + q(gateway) + "\n"
        "  ntp_servers:\n" + "".join("    - " + q(n) + "\n" for n in ntp) +
        "node:\n"
        "  ha_mode: Standalone\n"
        "  hostname: " + q(hostname) + "\n"
        "  features:\n    - metadata\n"
        "  networks:\n    " + q(interface) + ":\n"
        "      dhcp: false\n"
        "      ips:\n        - " + q(address + "/" + str(prefix)) + "\n"
        "      roles:\n        - data\n        - mgmt\n"
        "      mtu: 1500\n"
        "version: '1'\n"
    )

def prepare(args):
    if os.name != "posix":
        raise RuntimeError("Build on Linux: private artifact permissions are required")
    if not shutil.which("qemu-img"):
        raise RuntimeError("qemu-img is required")
    network = output(args.tool, "network")
    password = getpass.getpass("Hammerspace admin password: ")
    if not password or not any(not c.isalnum() for c in password):
        raise ValueError("Password must include a non-alphanumeric character")
    if password != getpass.getpass("Confirm password: "):
        raise ValueError("Passwords differ")
    text = yaml_config(network, args.hostname, args.domain, args.ntp, password, args.interface)
    GENERATED.mkdir(mode=0o700, exist_ok=True)
    os.chmod(GENERATED, 0o700)
    raw = GENERATED / "config.raw"
    qcow = GENERATED / "config.qcow2"
    placeholder = GENERATED / "placeholder"
    if raw.exists() or (qcow.exists() and not placeholder.exists()):
        raise RuntimeError("Config disk already exists; do not overwrite a deployment's configuration")
    try:
        write_raw(raw, text)
        tmp = GENERATED / "config.tmp.qcow2"
        run(["qemu-img", "convert", "-f", "raw", "-O", "qcow2", str(raw), str(tmp)])
        tmp.replace(qcow)
        os.chmod(qcow, 0o600)
        placeholder.unlink(missing_ok=True)
        (GENERATED / "ready").touch(mode=0o600)
    finally:
        raw.unlink(missing_ok=True)
    print("Created private .generated/config.qcow2; it contains the admin password.")

def init_artifacts():
    if os.name != "posix":
        raise RuntimeError("Run on Linux")
    GENERATED.mkdir(mode=0o700, exist_ok=True)
    os.chmod(GENERATED, 0o700)
    path = GENERATED / "config.qcow2"
    if path.exists():
        raise RuntimeError("Artifacts already exist; refusing to overwrite")
    run(["qemu-img", "create", "-f", "qcow2", str(path), "1G"])
    os.chmod(path, 0o600)
    (GENERATED / "placeholder").touch(mode=0o600)

def create(args):
    data = output(args.tool, "bootstrap")
    if any(not data.get(k) for k in
           ("project_id", "region", "name", "nic_id", "boot_id", "metadata_id", "config_id")):
        raise ValueError("Infrastructure outputs incomplete; apply the volume targets first")
    cli = ["stackit", "--project-id", data["project_id"], "--region", data["region"]]
    servers = json.loads(run(cli + ["server", "list", "-o", "json"], capture=True))
    if not isinstance(servers, list):
        raise ValueError("Unexpected server list response; refusing to create a duplicate")
    existing = [s for s in servers if s.get("name") == data["name"]]
    if len(existing) > 1:
        raise ValueError("Multiple matching servers; manual reconciliation required")
    if existing:
        server_id = existing[0].get("id") or existing[0].get("serverId")
        if args.resume_server_id != server_id:
            raise ValueError("Existing name found; inspect volumes/NIC, then supply --resume-server-id")
        details = json.loads(run(cli + ["server", "describe", server_id, "-o", "json"], capture=True))
        nics = details.get("nics", [])
        # Never import an unrelated server just because its name matches.
        if not any(n.get("nicId") == data["nic_id"] for n in nics):
            raise ValueError("Existing server has a different NIC; refusing import")
        print("Existing matching server found; resuming import.")
    else:
        if args.resume_server_id:
            raise ValueError("Requested resume server not found under this name/project")
        answer = json.loads(run(cli + [
            "server", "create", "--name", data["name"],
            "--machine-type", data["machine_type"],
            "--availability-zone", data["availability_zone"],
            "--network-interface-ids", data["nic_id"],
            "--boot-volume-source-type", "volume",
            "--boot-volume-source-id", data["boot_id"],
            "--volumes", data["config_id"] + "," + data["metadata_id"],
            "--agent-provisioning-policy", "NEVER",
            "--assume-yes", "-o", "json"], capture=True))
        server_id = answer.get("id") or answer.get("serverId")
    if not server_id:
        raise ValueError("No server ID returned; inspect STACKIT before retrying")
    print("Server ID:", server_id)
    state = set(tf(args.tool, "state", "list", capture=True).splitlines())
    base = data["project_id"] + "," + data["region"] + "," + server_id
    imports = [
        ("stackit_server.anvil", base),
        ("stackit_server_volume_attach.config", base + "," + data["config_id"]),
        ("stackit_server_volume_attach.metadata", base + "," + data["metadata_id"]),
    ]
    for address, identifier in imports:
        if address not in state:
            tf(args.tool, "import", address, identifier)
    print("Imported VM and attachments. Run plan and review before any further apply.")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool", choices=["terraform", "tofu"], default="terraform")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init-artifacts")
    p = sub.add_parser("prepare")
    p.add_argument("--hostname", default="hs-anvil-01")
    p.add_argument("--domain", required=True)
    p.add_argument("--ntp", nargs="+", required=True)
    p.add_argument("--interface", default="eth0",
                   help="Appliance NIC name; verify against console/boot logs")
    c = sub.add_parser("create")
    c.add_argument("--resume-server-id", help="Resume import only after verifying all disk IDs and NIC")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.command == "init-artifacts":
            init_artifacts()
        elif args.command == "prepare":
            prepare(args)
        else:
            create(args)
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print("ERROR:", exc, file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
