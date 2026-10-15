# Hammerspace on STACKIT: Anvil and DSX prototype

The standalone Anvil has been installed successfully in the STACKIT PoC, including
static IP configuration and admin password. The DSX extension awaits its first live
test. Uses the existing
STACKIT provider, not a new custom provider. No HA provisioning and no appliance
code patches. For a pair, deploy the Anvil below and then follow
[the DSX workflow](dsx/README.md) in its separate state. Existing project, IPv4 network, security groups and uploaded
Hammerspace **5.2.14-1267** image with **uefi=false** are required.

Defaults: g1a.16d; boot 200 GB storage_premium_perf1; metadata 400 GB
storage_premium_perf13; config disk 1 GB storage_premium_perf1; agent policy NEVER.

## Requirements and authentication

Run on Linux with Terraform >=1.6 (or compatible OpenTofu), Python 3,
qemu-img and the STACKIT CLI. The STACKIT provider is pinned to 0.120.0.
Keep the generated provider lockfile and verify its checksums on init.

Create/download a service-account JSON key using the
[root README instructions](../README.md#authenticate-the-cli), with permissions
for images, volumes, NICs, networks, servers and your security groups:

```bash
export STACKIT_SERVICE_ACCOUNT_KEY_PATH="$HOME/.config/stackit/hammerspace.json"
chmod 600 "$STACKIT_SERVICE_ACCOUNT_KEY_PATH"
stackit auth activate-service-account
```

The provider uses this environment variable independently of CLI login.
CLI calls below pass project and region explicitly.

## Why a staged bootstrap?

The provider's server resource does not accept additional volumes in its create
request. Its inactive status stops an already-created server; it does not guarantee
a stopped first boot. Attaching a config disk later risks missing first-boot
provisioning.

Therefore Terraform creates the NIC and disks; a small helper creates the VM
through `stackit server create --volumes ...` with both extra disks in the initial
request, then imports the server and both attachments into Terraform state.
After that, normal Terraform plans manage the resources.
**Do not run a full apply before completing these stages.**

## First deployment

Use one working directory/state per deployment. Commands assume the standard
`terraform.tfvars` filename so the helper's output/import commands load it too.
For OpenTofu, replace terraform commands with tofu and pass `--tool tofu` before
the helper subcommand.

```bash
cd terraform
umask 077
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: project/network/image/security-group IDs; no passwords.
terraform init
python3 scripts/bootstrap.py init-artifacts
terraform fmt -check
terraform validate

# 1: create only the NIC and read the existing network.
terraform plan -target=stackit_network_interface.anvil
terraform apply -target=stackit_network_interface.anvil
terraform apply -refresh-only
terraform output network

# 2: write the raw YAML disk, using that exact NIC IP and network settings.
# Substitute your domain, reachable NTP service and actual appliance NIC name.
python3 scripts/bootstrap.py prepare --domain poc.example --ntp pool.ntp.org --interface eth0

# 3: upload the config image and create all three volumes.
terraform plan -target=stackit_volume.boot -target=stackit_volume.metadata -target=stackit_volume.config
terraform apply -target=stackit_volume.boot -target=stackit_volume.metadata -target=stackit_volume.config

terraform apply -refresh-only
terraform output bootstrap

# 4: create VM with all disks, then import it and its attachments.
python3 scripts/bootstrap.py create

# 5: reconcile the imported configuration. Review any proposed changes.
terraform plan
terraform output management_url
```

Targeting is intentional for this first-boot workaround, not the normal day-to-day
workflow. Following import, review the plan for any differences and investigate
replacements or unexpected updates instead of applying blindly.

Boot-source fields are ignored on the imported server because the API does not
return them; the separate boot-volume resource still manages the volume.
Check its actual attachment in STACKIT when reconciling a deployment.
Imported NIC lists and agent provisioning policy are also ignored due provider
0.120.0 import limitations. Verify the actual NIC/boot attachments in STACKIT.

An import failure does not delete
the VM. The helper prints its ID; inspect the server and resume with
`python3 scripts/bootstrap.py create --resume-server-id <SERVER_ID>` only after
confirming boot/config/metadata volume IDs and NIC match `terraform output bootstrap`.

If creation fails part-way, inspect STACKIT server list before retrying.
The helper refuses to create another VM with the same name.
A local artifact must not be regenerated/overwritten for a running deployment.
Changing a config disk is not an appliance reconfiguration mechanism.

## Config-disk contract and verification

The helper uses Hammerspace's own GenericProv: installer YAML starts at byte zero,
followed by **2 MiB of newline padding**, with the virtual disk extended to 1 GiB
and converted to QCOW2. No filesystem and no cloud-init package are required.
The padding is needed for the guest's `file -bs /dev/vdX` to report ASCII text.
The initial empty placeholder lets provider validation check its required file
path before NIC creation. An image precondition blocks its upload until prepare
has replaced it with the real configuration disk.
The YAML uses the single `node` form, Standalone metadata role, static IPv4
matching the STACKIT NIC, network gateway/DNS, and supplied NTP/domain.

Verify in console/boot logs that the config disk is read, the real interface name
matches, and the 400 GB metadata disk is selected. Check the management UI and
authenticated API on port 8443; a running VM alone does not prove installation.
Allow roughly 15 minutes as an initial observation window, not a readiness guarantee.

Still to validate on STACKIT: image import of this config disk, allowed minimum
volume size, exact imported server attributes, disk enumeration, interface naming,
and successful first boot on 5.2.14-1267. No Nebius phantom-disk/GRUB patches are
included. The main image's BIOS property must already be correct.

## Secrets, cleanup and destroy

The password is prompted (not echoed) and is **not** a Terraform input.
It remains in plaintext inside `.generated/config.qcow2`, its cloud image and
config volume. Directory/file permissions are 0700/0600. Keep state, plan files,
credentials and generated images private and outside Git; sensitive infrastructure
details can still be present in state. Use a protected backend for shared work.

After successful provisioning, remove the config attachment, config volume and
config image resource blocks together, remove their references from the bootstrap
output, and review/apply that cleanup plan; keep the boot and metadata volumes.
Then delete the local `.generated` artifacts. This first prototype leaves cleanup
explicit so you can inspect provisioning before removing the evidence.

The VM has `prevent_destroy=true`. Destruction/replacement requires deliberately
removing that protection and reviewing the plan. A full destroy deletes the
Terraform-managed volumes (including metadata) and NIC, but never the existing
project/network/security groups or shared Hammerspace base image.
Use [the separate DSX workflow](dsx/README.md) to add a DSX to this Anvil.
