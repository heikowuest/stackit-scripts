# Add a DSX to the standalone STACKIT Anvil

This separate root configuration/state adds one DSX to an existing Anvil.
For a fresh pair, first deploy the Anvil using [../README.md](../README.md),
verify its admin login/API, then run this workflow. The existing Anvil is not
managed or recreated by this DSX state.

## Defaults and prerequisites

Same clean Hammerspace 5.2.14-1267 image (uefi=false), region/AZ and authentication
as the Anvil. DSX defaults: g1a.16d (the already tested VM type), 200 GB boot and
1000 GB data, both storage_premium_perf1, plus a 1 GB config disk. Agent NEVER.
These are PoC defaults, not a production sizing recommendation.

Security groups must allow bidirectional Anvil/DSX communication, including Salt
TCP 4505/4506, and required Hammerspace storage traffic. A group named "default"
does not prove this. The deploying Linux host must reach the Anvil API on 8443.
Use the same cluster domain and admin password as the Anvil.

## Deployment

Run from this dsx directory with Terraform >=1.6, Python >=3.9, qemu-img and
STACKIT CLI. Set STACKIT_SERVICE_ACCOUNT_KEY_PATH and activate the CLI service
account as documented in the parent. OpenTofu users replace terraform with tofu
and pass --tool tofu to the helper (before its subcommand).

```bash
cd terraform/dsx
umask 077
cp terraform.tfvars.example terraform.tfvars
# Edit IDs and anvil_ip. Do not put the cluster password into tfvars.
terraform init
python3 ../scripts/bootstrap.py --role dsx init-artifacts
terraform validate

terraform plan -target=stackit_network_interface.dsx
terraform apply -target=stackit_network_interface.dsx
# Targeted applies may omit new outputs. Refresh-only changes no cloud resources.
terraform apply -refresh-only
terraform output network

# Use the SAME domain/NTP as the Anvil and its actual interface name.
python3 ../scripts/bootstrap.py --role dsx prepare \
  --domain poc.example --ntp pool.ntp.org --interface eth0

terraform plan -target=stackit_volume.boot -target=stackit_volume.data -target=stackit_volume.config
terraform apply -target=stackit_volume.boot -target=stackit_volume.data -target=stackit_volume.config
terraform apply -refresh-only
terraform output bootstrap

python3 ../scripts/bootstrap.py --role dsx create
terraform plan
```

The prompt requests the existing Anvil admin password twice; the helper verifies
it against https://ANVIL_IP:8443/mgmt/v1.2/rest/nodes before building the config
disk. Self-signed certificates are accepted for this PoC (as with curl -k).
A password/API/network failure stops preparation; it does not create a DSX VM.

If the deploying host has no route/VPN into the private STACKIT network, skip only
this deploy-host API/password check:

```bash
python3 ../scripts/bootstrap.py --role dsx prepare \\
  --domain poc.example --ntp pool.ntp.org --interface eth0 --skip-anvil-check
```

The existing Anvil password must still be supplied correctly. YAML generation,
password confirmation, assigned static DSX IP and Anvil join address are unchanged.
The DSX joins the Anvil from inside STACKIT. This flag does not bypass cluster
authentication or change any security-group rules. By default the API check remains enabled.

The DSX YAML uses static IPv4 assigned to its own STACKIT NIC, cluster.metadata.ips
pointing at the Anvil, storage/portal features and add_node=true. GenericProv's
ASCII YAML disk mechanism is reused. All disks are attached at VM creation,
then the server and config/data attachments are imported into this separate state.
The output metadata_id is retained as an internal helper compatibility field;
in this DSX state it refers to the DSX DATA volume.

Check the Anvil UI/CLI node list for a managed/online DSX. Verify its local data
disk before registering it as a writable backend volume in the Anvil UI. The
Anvil management URL remains the Anvil IP; DSX management_url is diagnostic.

## Config disk and volume registration

Default add_volumes=false deliberately joins the DSX without automatically
registering its discovered disks as cluster volumes. Hammerspace may format
ALL non-boot disks during DSX first boot, including the 1 GB config disk, even
with add_volumes=false. After joining, register only the intended 1000 GB data
volume; do not register the small config disk.

Optional prepare --register-volumes sets add_volumes=true. This can register the
config disk as a junk 1 GB storage volume too. Inspect and remove that volume
through Hammerspace before detaching/deleting its cloud disk. Do not enable this
unless you intend to perform that cleanup.

After verifying the DSX join and storage, remove the config image, config volume,
config attachment blocks and bootstrap output config_id reference, review the
cleanup plan and apply. Do not remove the data attachment/volume. Then remove
local .generated artifacts. Config image/volume must be treated as containing
the plaintext cluster password regardless of what the guest does to its disk.

VM deletion is protected by prevent_destroy. Imported boot source, NIC list and
agent policy are ignored due provider 0.120.0 import limitations; verify actual
NIC/boot/data attachments in STACKIT. Do not run a full apply before bootstrap
and import. On interrupted imports inspect the VM and use --resume-server-id as
described in the parent README.

## Validation status

Anvil installation, static IP and admin password via ASCII config disk have been
confirmed in the user-run STACKIT PoC. DSX creation/join and local-volume state must be verified on resume.
No Nebius-specific GRUB/phantom-disk patches are applied. No HA is configured.
Keep generated disks, state, tfvars and credentials outside Git.
