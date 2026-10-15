# Hammerspace on STACKIT PoC

Bash scripts for uploading a Hammerspace appliance image to STACKIT and deploying a test VM with separate boot and metadata volumes. This documents the current tested PoC workflow.

## Prerequisites and STACKIT setup

- Linux/Bash with `stackit` CLI, `jq`, and `curl`; optionally `qemu-img` to inspect the image.
- A STACKIT project with sufficient compute/storage quota and an existing IPv4 network, gateway, DNS, and suitable connectivity/security rules for appliance management.
- A service account with permissions to manage images, volumes, servers, and network attachments; configure service-account authentication locally for the CLI.
- Select the intended project/region in the CLI and match the configuration blocks in both scripts. The scripts currently contain PoC-specific IDs: replace project, network, image, availability zone, and VM name as appropriate. Configuration is edited in the scripts, not passed as command-line arguments.
- Obtain the Hammerspace QCOW2 image separately; it is not distributed here.

## Authenticate the CLI

In the STACKIT Portal, select the target project and open **IAM and Management > Service accounts**. Select a service account with the required project permissions, open **Service Account Keys**, choose **+ Create service account key > Create new key pair**, optionally set an expiry, and select **Create**. Download/save the generated service-account JSON securely on the Linux host as, for example, `$HOME/.config/stackit/hammerspace.json` (outside this repository).

Use the generated key-pair flow for this example. If you upload your own public key instead, the generated JSON does not include the private key and requires separate private-key configuration. See the [official STACKIT key instructions](https://docs.stackit.cloud/platform/access-and-identity/service-accounts/how-tos/manage-service-account-keys/).

Run the following directly in the shell; no local `auth-*.sh` script is required. Replace `<PROJECT_ID>` with your target project ID:

```bash
chmod 600 "$HOME/.config/stackit/hammerspace.json"

export STACKIT_SERVICE_ACCOUNT_KEY_PATH="$HOME/.config/stackit/hammerspace.json"

stackit auth activate-service-account
stackit config set --project-id "<PROJECT_ID>"
stackit config list

# Verify access before uploading or deploying
stackit image list
stackit server list
```

The exported path applies to the current shell; set it again in a new shell before activating the service account. Match the CLI project to `PROJECT_ID` in both scripts. Never paste the JSON contents into this repository.

## 1. Upload the image

Current tested image: **Hammerspace `5.2.14-1267`**, file `hammerspace-5.2.14-1267.qcow2`.

Set `PROJECT_ID`, `REGION`, and `IMAGE_FILE` in [upload-image-hammerspace.sh](upload-image-hammerspace.sh), place the QCOW2 in the working directory, then run:

```bash
bash upload-image-hammerspace.sh
```

The script checks tools/authentication and duplicate image names, creates an image object, uploads the QCOW2 using the returned upload URL, and waits until import is `AVAILABLE`. Record the returned image ID for deployment.

**Boot compatibility:** Hammerspace **5.2.x QCOW2 currently requires legacy BIOS**. Set the imported STACKIT image's `uefi=false` property before creating the VM; the upload script does not currently set it. Hammerspace **5.3.x is expected to support UEFI**, but that is not validated by this PoC.

## 2. Deploy the VM

Set the target configuration and imported `IMAGE_ID` in [create-hammerspace-vm.sh](create-hammerspace-vm.sh), then run:

```bash
bash create-hammerspace-vm.sh
```

The script creates both volumes, waits for them to become available, and creates the server with the metadata volume attached.

| Setting | Current tested default |
| --- | --- |
| Machine type | `g1a.16d` |
| Boot volume | 200 GB, `storage_premium_perf1` |
| Metadata volume | 400 GB, `storage_premium_perf13` |
| Agent provisioning | Disabled: `--agent-provisioning-policy NEVER` |

STACKIT assigns the NIC IPv4 address. The script reads that address from the server NIC and reads the prefix, gateway, and DNS servers from the associated network, then prints the values for appliance setup.

## 3. Configure Hammerspace networking manually

Open the appliance console/setup and configure **exactly the IPv4 address assigned by STACKIT to that NIC as a static address in Hammerspace**, together with the printed prefix, gateway, and DNS.

Do not choose an arbitrary static guest IP: STACKIT NIC security/anti-spoofing rejects traffic when the guest address does not match the assigned NIC address.

Fixed-IP NIC provisioning and deployment through Terraform/OpenTofu are future work.

## Repository safety

`.gitignore` excludes JSON files (`*.json`, including service-account keys), local auth scripts (`auth-*.sh`), QCOW2/raw/ISO images, and customer-specific file patterns.

**Never commit credentials, passwords, tokens, authentication scripts, service-account JSON keys, QCOW2 images, or customer-specific data.** Keep these outside version control and verify ignore coverage for any new filenames; ignore rules do not protect files already tracked by Git.
