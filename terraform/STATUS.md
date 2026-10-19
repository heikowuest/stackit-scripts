# PoC checkpoint — 2026-10-19

The owner reported both prior VM deployments deleted for a clean retest.
Earlier confirmed: Anvil 5.2.14-1267/BIOS, ASCII YAML bootstrap, static IPv4,
admin password and ONLINE status. DSX data registration was not completed.

The next test follows [RETEST.md](RETEST.md):
1. Fresh Anvil.
2. DSX boot + config only, add_volumes=false.
3. Verify DSX join and observe config disk behavior.
4. Remove DSX config attachment, disk and image via Terraform.
5. Live-attach a 1000 GB data disk via Terraform.
6. drive-list -> logical-volume-create -> volume-add/API registration.

Correction: add_volumes=false is treated as disabling local DSX volume
preparation (filesystem, mount, export) as well as cluster registration,
per the user's appliance experience. Earlier claims that it only controls
registration are superseded.

Local schema/unit tests do not prove this new flow on STACKIT. Live test pending.
The REST request for cluster volume registration is evidenced by the public
Operations playbook; drive/logical-volume REST operations remain unverified,
so the checklist uses the known Hammerspace CLI for those steps.

No cloud deployment/deletion has been executed by Codex. Keep actual addresses,
credentials, local tfvars and state private. New NIC IPs must be discovered again.
