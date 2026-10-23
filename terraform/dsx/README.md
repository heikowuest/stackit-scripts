# DSX deployment: bootstrap first, data disk later

Follow the complete [retest checklist](../RETEST.md). This root has its own state;
the parent root manages the Anvil. Keep both states and local tfvars private.

## Phases

| Phase | keep_config_disk | attach_data_disk | Result |
|---|---|---|---|
| Bootstrap | true | false | Boot + YAML config disk; no data disk |
| Config cleanup, after verified cluster join | false | false | Detach/delete config disk and image |
| Data | false | true | Create and live-attach 1000 GB data disk |

Persist these flags in terraform.tfvars at each phase. Do not use transient
-var overrides: a later apply with old defaults could recreate the config disk
or delete the data disk. Never set attach_data_disk=false on a used volume
without first decommissioning it safely in Hammerspace.

Defaults: g1a.16d, boot 200 GB storage_premium_perf1, data 1000 GB
storage_premium_perf1, config 1 GB, agent NEVER; Hammerspace 5.2.14-1267/BIOS.
The public API management endpoint belongs to the Anvil, not the DSX.

add_volumes=false remains the installer setting. Based on the user's appliance
experience it disables local volume setup (XFS/mount/export) as well as cluster
volume registration. Earlier statements claiming it only controls cluster
registration were too broad and are superseded by this workflow.

After join, inspect drives/local volumes before removing the config disk. If
it was unexpectedly initialized or registered, stop and clean it up through
Hammerspace before detaching. No guest filesystem is modified by Terraform.

The data phase only attaches a cloud disk. Inspect it with drive-list, then
use Hammerspace logical-volume-create for the verified device and register the
resulting logical volume/export with volume-add or the documented REST workflow
in RETEST.md. Do not run generic mkfs/mount/export commands behind Hammerspace.

The exact REST endpoint equivalent of logical-volume-create remains unverified.
No guessed API request or automatic guest formatting is included.

## Migration warning

This workflow is intended for the clean redeployment requested by the owner.
Migration blocks are supplied as moved.tf.example, NOT loaded by default, because
active moved blocks conflict with the targeted fresh-bootstrap plans. Only for
an existing pre-count deployment, back up state and enable the example explicitly
before a reviewed migration plan. Do not enable it for a fresh deployment.

The new defaults
do NOT preserve an existing data disk: an existing deployed state must retain
attach_data_disk=true when it owns live data. The phase guard additionally
requires config removal before data can be attached.
Review migration plans; do not apply this fresh-deployment sequence to a live cluster.

VM deletion remains protected. Import limitations for boot source, NIC list and
agent policy remain handled as in the parent. The bootstrap helper imports the
DSX server and config attachment only; it never attaches/imports a data disk at
initial creation. --skip-anvil-check skips only the deploying host's API check.

Local tests/schema checks are not a substitute for live validation: this new
two-phase flow still needs the next user-run test.
