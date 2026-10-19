# Retest TODO — fresh Anvil + DSX, then 1 TB DSX data

Prepared 2026-10-19. Run on the Linux admin host unless a section explicitly
says Hammerspace CLI. Nothing in this checklist has been executed by Codex.
It assumes both previous VM deployments were destroyed as reported by the owner.
Do not reuse this sequence on an existing cluster holding data.

Replace placeholders before running. Do not reuse old NIC IPs: STACKIT assigns
new addresses on this deployment. Shell examples use Terraform; for OpenTofu
replace terraform with tofu and add --tool tofu to bootstrap.py before its subcommand.

## 0. Update, authenticate, check local state

```bash
cd "$HOME/stackit"
git pull --ff-only origin main
export STACKIT_SERVICE_ACCOUNT_KEY_PATH="$HOME/stackit/hammerspace.json"
test -r "$STACKIT_SERVICE_ACCOUNT_KEY_PATH"
stackit auth activate-service-account
umask 077

cd terraform
terraform state list
(cd dsx && terraform state list)
```

Both states should contain no managed PoC resources after the previous destroys.
If they still contain VM/disk resources, reconcile them before continuing.
Keep local tfvars; never commit credentials, state, plans or generated disks.
Ensure teardown_override.tf from the previous destroy is gone in BOTH roots.
Use terraform.tfvars.example only if you no longer have local tfvars.

```bash
test ! -e teardown_override.tf
test ! -e dsx/teardown_override.tf
```

Inspect the retained Hammerspace image in STACKIT: 5.2.14-1267, uefi=false.
For this private PoC, both NICs can use the existing default security group,
whose self-referencing ingress permits their mutual traffic. The Linux admin
host may still have no private route. Public management access, if used, needs
an Anvil public IP and suitable management ingress; update Anvil local tfvars
with every manually attached group. No public IP is required on the DSX.

## 1. Anvil: NIC, config, disks, VM

```bash
terraform init
terraform fmt -check
# Fresh artifacts only. If this reports existing artifacts, inspect them;
# do not overwrite configuration belonging to an installed VM.
python3 scripts/bootstrap.py init-artifacts
terraform validate

terraform plan -target=stackit_network_interface.anvil
terraform apply -target=stackit_network_interface.anvil
terraform apply -refresh-only
terraform output network
```

Expected: one new Anvil NIC. Record its NEW private IP.

```bash
python3 scripts/bootstrap.py prepare \
  --hostname hs-anvil-01 --domain poc.example --ntp pool.ntp.org --interface eth0

terraform plan -target=stackit_volume.boot -target=stackit_volume.metadata -target=stackit_volume.config
terraform apply -target=stackit_volume.boot -target=stackit_volume.metadata -target=stackit_volume.config
terraform apply -refresh-only
terraform output bootstrap

python3 scripts/bootstrap.py create
terraform plan
```

Expected: config image + three volumes; VM create imports the Anvil and two
attachments. No server replacement in the reconciliation plan. Wait for ONLINE
in the portal console and verify admin password login. Observe the 400 GB metadata
disk. No DSX/storage capacity is expected yet. Do not remove the Anvil config
resources with the DSX phase flags; those flags exist only in the DSX root.

## 2. DSX: bootstrap with NO data disk

```bash
cd dsx
# Edit existing local tfvars or copy the example if absent.
test -f terraform.tfvars || cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Set anvil_ip to the NEW Anvil private IP. Set these values in tfvars:

```hcl
keep_config_disk = true
attach_data_disk = false
data_volume_size = 1000
```

Use the same project/network/image/security groups, cluster domain and cluster
admin password as the Anvil. The DSX name defaults to hs-poc-dsx.

```bash
terraform init
python3 ../scripts/bootstrap.py --role dsx init-artifacts
terraform validate
terraform plan -target=stackit_network_interface.dsx
terraform apply -target=stackit_network_interface.dsx
terraform apply -refresh-only
terraform output network

python3 ../scripts/bootstrap.py --role dsx prepare \
  --hostname hs-dsx-01 --domain poc.example --ntp pool.ntp.org --interface eth0 \
  --skip-anvil-check

terraform plan -target=stackit_volume.boot -target=stackit_volume.config
terraform apply -target=stackit_volume.boot -target=stackit_volume.config
terraform apply -refresh-only
terraform output bootstrap

python3 ../scripts/bootstrap.py --role dsx create
terraform plan
```

Expected volume stage: THREE new resources (config image, boot disk, config disk),
NOT four. No stackit_volume.data resource. bootstrap.metadata_id=null is expected
for the DSX now. The helper creates the VM with ONLY the config disk in --volumes
and imports server + config attachment.

## 3. Verify DSX join and config disk behavior

In the Anvil Hammerspace CLI:

```text
node-list
drive-list --node-name hs-dsx-01.poc.example --format table --full
```

Confirm the DSX is joined/online and inspect local volumes in the UI. Record
whether the 1 GB config disk was left untouched, formatted/mounted/exported,
or registered in the cluster. This is a test observation, not an assumption.

If that disk is an active local/registered volume, STOP and remove it safely
through Hammerspace before cloud detachment. Do not remove boot storage.
There is no production data disk in this phase.

## 4. Terraform: remove DSX config disk and config image

On Linux admin, still in terraform/dsx:

```bash
nano terraform.tfvars
```

Change the two phase values, leaving IDs/password-independent settings intact:

```hcl
keep_config_disk = false
attach_data_disk = false
```

```bash
terraform plan -out=config-cleanup.tfplan
```

Expected: destroy ONLY config attachment, 1 GB config disk and config image
(three resources). No VM/NIC/boot deletion or replacement.

```bash
terraform apply config-cleanup.tfplan
terraform state list
terraform plan
```

Confirm in the portal that only the 200 GB boot disk is attached to the DSX.
The helper is no longer used after import. Local config artifacts still contain
the password; after cloud cleanup succeeds remove only this DSX directory:

```bash
rm -rf -- ./.generated
rm -f -- config-cleanup.tfplan
```

The disabled config resource uses an existing documentation path only for static
provider validation; it has count=0 and uploads no file.

## 5. Terraform: attach the 1 TB data disk live

```bash
nano terraform.tfvars
```

Persist:

```hcl
keep_config_disk = false
attach_data_disk = true
data_volume_size = 1000
```

```bash
terraform plan -out=data-attach.tfplan
```

Expected: create data volume + data attachment (two resources), with no VM
replacement. Do not proceed if config artifacts would be recreated.

```bash
terraform apply data-attach.tfplan
terraform output data_volume_id
terraform plan
rm -f -- data-attach.tfplan
```

## 6. Hammerspace: discover and prepare the selected data device

In the Anvil Hammerspace CLI:

```text
drive-list --node-name hs-dsx-01.poc.example --format table --full
```

Match the newly attached 1000 GB cloud disk to the guest device. Do not hard-code
/dev/nvme0n3 or /dev/vdb: naming can change after config detachment. Compare size
and device identity/serial with the STACKIT volume; never select the boot disk.

Only after verifying that mapping, replace VERIFIED_DATA_DEVICE below:

```text
logical-volume-create --node-name hs-dsx-01.poc.example --device-path VERIFIED_DATA_DEVICE
```

This is the user's known Hammerspace operation for local preparation. Wait for
completion and record the actual resulting logical-volume/export name from the
CLI/UI. Do not assume /hsvol0. Verify XFS, mount and export through Hammerspace.

The REST endpoint for drive discovery/local logical-volume creation has not
been verified from the public Operations examples; those steps remain CLI-driven.
Do not substitute generic Linux mkfs/mount/export commands.

## 7. Register the prepared volume in the cluster

Use volume-add in the Hammerspace CLI/Web UI with the actual DSX and actual
logical-volume/export name, or the REST equivalent below. Do ONE method, not both.

The POST body and async completion pattern are based on:
https://github.com/hammer-space/ansible/blob/main/Operations/storage-volume-add.yml

Run this REST alternative from a host with access to the Anvil API. The private
IP is not reachable from the Linux admin host without a route/VPN; use your
properly restricted public Anvil endpoint if appropriate. Password is prompted
by curl and is not embedded in JSON or command arguments.

```bash
read -rp "Anvil API origin, e.g. https://ANVIL:8443: " HS_ORIGIN
read -rp "DSX FQDN, e.g. hs-dsx-01.poc.example: " DSX_FQDN
read -rp "Verified logical-volume/export name: " HS_LOGICAL_VOLUME
read -rp "New friendly cluster volume name: " HS_VOLUME_NAME
umask 077
mkdir -p .generated
chmod 700 .generated

jq -n --arg name "$HS_VOLUME_NAME" --arg lv "$HS_LOGICAL_VOLUME" --arg node "$DSX_FQDN" \
  '{name:$name,logicalVolume:{name:$lv,_type:"LOGICAL_VOLUME"},node:{name:$node,_type:"NODE"},_type:"STORAGE_VOLUME",accessType:"READ_WRITE"}' \
  > .generated/volume-add.json

curl --fail-with-body -k --connect-timeout 10 --max-time 180 \
  -u admin -D .generated/volume-add.headers \
  -H 'Content-Type: application/json' \
  --data-binary @.generated/volume-add.json \
  "$HS_ORIGIN/mgmt/v1.2/rest/storage-volumes?force=true"
```

Expected HTTP 202 and a Location header for the asynchronous task. Inspect headers:

```bash
cat .generated/volume-add.headers
read -rp "Verified task URL from Location header: " HS_TASK_URL
curl --fail-with-body -k --connect-timeout 10 --max-time 60 -u admin "$HS_TASK_URL"
```

If Location is relative, prefix the same Anvil API origin. Check that the URL
belongs to your Anvil before supplying credentials. Repeat task GET until
COMPLETED; stop on a failed task and inspect its error rather than repeating POST.
Self-signed TLS is accepted here only for the PoC, matching the upstream playbook.

## 8. Acceptance / record results

- Anvil ONLINE, DSX joined/online.
- DSX has boot + intended 1000 GB data disk; no 1 GB config disk.
- Intended logical volume is prepared and registered READ_WRITE.
- No config disk listed as a storage volume.
- Terraform plans show no infrastructure changes in either root.
- Save disk mapping and observed config-disk behavior without passwords.
- A persistent data disk must be safely decommissioned in Hammerspace BEFORE
  detaching/deleting it. Never toggle attach_data_disk=false casually.
