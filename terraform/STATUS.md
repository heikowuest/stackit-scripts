# PoC checkpoint — 2026-10-15

## Confirmed in the user-run environment

- Hammerspace 5.2.14-1267, legacy BIOS (uefi=false).
- Standalone Anvil installed unattended using the ASCII YAML config disk.
- Static NIC IPv4, domain/hostname and admin password were taken from the config.
- Anvil reports ONLINE and admin console authentication works.
- Terraform imports completed; NIC/agent import differences were corrected.
- DSX NIC and boot/config/data volumes were created. VM startup/join and the
  final DSX state have not been supplied to this chat; verify on resume.
- DSX add_volumes=false: automatic Hammerspace backend-volume registration
  is deliberately disabled, even if its local disks have been prepared.
- The deploying Linux host has no private network route to the Anvil.
  Use --skip-anvil-check when preparing DSX YAML from that host.
- User added a public IP and an HTTPS security group to the Anvil manually.
  Copy the actual group IDs into the local Anvil tfvars before any normal apply.
  Reconcile/import the public IP into Terraform before managing it there.
  External access began working after a short propagation delay.

No customer-specific resource IDs, passwords or screenshots are stored here.

## Planned next step: 1 TB DSX data

The DSX data_volume_size default is now 1000 GB (decimal 1 TB).
The existing PoC data volume was created at 100 GB. Set
data_volume_size = 1000 in the local DSX terraform.tfvars explicitly.

Do not apply the enlargement during the vacation pause. On resume, review a
targeted plan for stackit_volume.data: it should enlarge the existing data disk
in place, with no VM replacement and no disk deletion. No second data disk is
required for this plan. If a separate additional 1 TB disk is wanted instead,
model it as a new resource before applying.

Cloud volume enlargement/attachment alone does not register a writable backend
in Hammerspace. Inspect the DSX local volumes and the config disk first; then
expand/prepare the intended data volume as required and register only that
data volume with the Anvil using the supported Hammerspace UI/CLI/API.
This guest-side expansion/registration has NOT been automated or validated.
Never register the 1 GB config disk as a production data volume.

## Pause and resume

Earliest intended continuation: Monday, 2026-10-19.

Shutdown/deallocation is requested but not confirmed. Run the commands from the
Linux admin host (which has STACKIT credentials), then verify server state.
Deallocate DSX first, then Anvil, and any other PoC VMs explicitly selected by
the owner. Do not loop over every server in the project indiscriminately.

STACKIT stop/pause retains compute allocation and billing. Deallocate removes
compute allocation while preserving the VM and persistent volumes:
https://docs.stackit.cloud/products/compute-engine/server/basics/introduction-to-server/

Volumes and public IPs are separate retained resources; deallocation is not a
promise of zero overall project costs. No resource deletion is needed for this
pause. No cloud lifecycle action has been executed by Codex.

Keep both terraform state files, backups, local tfvars and generated artifacts
private. Save a private copy of each state before infrastructure changes.
On resume start Anvil first, verify ONLINE, then DSX and verify join/storage.
Do not run an ordinary Terraform apply while paused: explicitly review its
resource/state changes first. Do not regenerate config disks for installed nodes.
