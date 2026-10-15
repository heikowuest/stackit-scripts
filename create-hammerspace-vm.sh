#!/usr/bin/env bash

set -euo pipefail

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------

PROJECT_ID="c487a3ae-4569-4251-b81a-3241413edaf8"
REGION="eu01"
AZ="eu01-3"

VM_NAME="hs-test2"
MACHINE_TYPE="g1a.16d"

NETWORK_ID="8e2196a1-53bf-4d00-8378-f3cd71336b9a"

IMAGE_ID="2ad87f77-940f-4864-b2a7-99150c504ed5"

BOOT_VOLUME_NAME="${VM_NAME}-boot"
BOOT_VOLUME_SIZE=200
BOOT_PERF_CLASS="storage_premium_perf1"

METADATA_VOLUME_NAME="${VM_NAME}-metadata"
METADATA_VOLUME_SIZE=400
METADATA_PERF_CLASS="storage_premium_perf13"

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

wait_for_volume_available() {
    local volume_id="$1"

    echo "Waiting for volume ${volume_id} to become AVAILABLE..."

    while true; do
        state="$(
            stackit volume describe "${volume_id}" -o json |
            jq -r '.status // .state // empty'
        )"

        printf '%s  Volume %s state: %s\n' \
            "$(date '+%H:%M:%S')" \
            "${volume_id}" \
            "${state}"

        case "${state}" in
            AVAILABLE)
                return 0
                ;;

            ERROR|FAILED)
                echo "ERROR: Volume entered state ${state}"
                exit 1
                ;;

            *)
                sleep 5
                ;;
        esac
    done
}

# ----------------------------------------------------------------------
# Checks
# ----------------------------------------------------------------------

command -v stackit >/dev/null 2>&1 || {
    echo "ERROR: stackit CLI not found."
    exit 1
}

command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq not found."
    exit 1
}

echo "Checking STACKIT access..."

if ! stackit server list >/dev/null 2>&1; then
    echo "ERROR: Cannot access STACKIT project."
    exit 1
fi

echo "STACKIT access OK."
echo

# ----------------------------------------------------------------------
# Check that VM does not already exist
# ----------------------------------------------------------------------

if stackit server list -o json |
   jq -e --arg NAME "${VM_NAME}" \
      '.[]? | select(.name == $NAME)' >/dev/null; then

    echo "ERROR: Server '${VM_NAME}' already exists."
    exit 1
fi

# ----------------------------------------------------------------------
# Create boot volume
# ----------------------------------------------------------------------

echo "Creating boot volume..."

BOOT_OUTPUT="$(
    stackit volume create \
        --name "${BOOT_VOLUME_NAME}" \
        --availability-zone "${AZ}" \
        --source-type image \
        --source-id "${IMAGE_ID}" \
        --size "${BOOT_VOLUME_SIZE}" \
        --performance-class "${BOOT_PERF_CLASS}" \
        --assume-yes \
        -o json
)"

BOOT_VOLUME_ID="$(
    jq -r '.id // .volumeId // empty' <<<"${BOOT_OUTPUT}"
)"

if [[ -z "${BOOT_VOLUME_ID}" ]]; then
    echo "ERROR: Could not determine boot volume ID."
    echo "${BOOT_OUTPUT}" | jq .
    exit 1
fi

echo "Boot volume ID: ${BOOT_VOLUME_ID}"
echo

wait_for_volume_available "${BOOT_VOLUME_ID}"

echo

# ----------------------------------------------------------------------
# Create metadata volume
# ----------------------------------------------------------------------

echo "Creating metadata volume..."

METADATA_OUTPUT="$(
    stackit volume create \
        --name "${METADATA_VOLUME_NAME}" \
        --availability-zone "${AZ}" \
        --size "${METADATA_VOLUME_SIZE}" \
        --performance-class "${METADATA_PERF_CLASS}" \
        --assume-yes \
        -o json
)"

METADATA_VOLUME_ID="$(
    jq -r '.id // .volumeId // empty' <<<"${METADATA_OUTPUT}"
)"

if [[ -z "${METADATA_VOLUME_ID}" ]]; then
    echo "ERROR: Could not determine metadata volume ID."
    echo "${METADATA_OUTPUT}" | jq .
    exit 1
fi

echo "Metadata volume ID: ${METADATA_VOLUME_ID}"
echo

wait_for_volume_available "${METADATA_VOLUME_ID}"

echo

# ----------------------------------------------------------------------
# Create server
# ----------------------------------------------------------------------

echo "Creating Hammerspace VM..."

SERVER_OUTPUT="$(
    stackit server create \
        --name "${VM_NAME}" \
        --machine-type "${MACHINE_TYPE}" \
        --network-id "${NETWORK_ID}" \
        --boot-volume-source-id "${BOOT_VOLUME_ID}" \
        --boot-volume-source-type volume \
        --volumes "${METADATA_VOLUME_ID}" \
        --agent-provisioning-policy NEVER \
        --assume-yes \
        -o json
)"

SERVER_ID="$(
    jq -r '.id // .serverId // empty' <<<"${SERVER_OUTPUT}"
)"

if [[ -z "${SERVER_ID}" ]]; then
    echo "ERROR: Could not determine server ID."
    echo "${SERVER_OUTPUT}" | jq .
    exit 1
fi

echo
echo "Server created."
echo "Server ID: ${SERVER_ID}"
echo

# ----------------------------------------------------------------------
# Get final server and network configuration
# ----------------------------------------------------------------------

SERVER_JSON="$(
    stackit server describe "${SERVER_ID}" -o json
)"

IPV4="$(
    jq -r '.nics[0].ipv4 // empty' <<<"${SERVER_JSON}"
)"

SERVER_NETWORK_ID="$(
    jq -r '.nics[0].networkId // empty' <<<"${SERVER_JSON}"
)"

NETWORK_JSON="$(
    stackit network describe "${SERVER_NETWORK_ID}" -o json
)"

GATEWAY="$(
    jq -r '.ipv4.gateway // empty' <<<"${NETWORK_JSON}"
)"

PREFIX_CIDR="$(
    jq -r '.ipv4.prefixes[0] // empty' <<<"${NETWORK_JSON}"
)"

PREFIX_LEN="${PREFIX_CIDR##*/}"

DNS="$(
    jq -r '.ipv4.nameservers | join(", ")' <<<"${NETWORK_JSON}"
)"

# ----------------------------------------------------------------------
# Final status
# ----------------------------------------------------------------------

echo
echo "============================================================"
echo "Hammerspace VM created successfully"
echo "============================================================"
echo
echo "Server:"
echo "  Name          : ${VM_NAME}"
echo "  Server ID     : ${SERVER_ID}"
echo "  Machine Type  : ${MACHINE_TYPE}"
echo "  AZ            : ${AZ}"
echo
echo "Storage:"
echo "  Boot Volume   : ${BOOT_VOLUME_ID}"
echo "  Boot Size     : ${BOOT_VOLUME_SIZE} GB"
echo "  Boot Perf     : ${BOOT_PERF_CLASS}"
echo
echo "  Metadata Vol  : ${METADATA_VOLUME_ID}"
echo "  Metadata Size : ${METADATA_VOLUME_SIZE} GB"
echo "  Metadata Perf : ${METADATA_PERF_CLASS}"
echo
echo "Hammerspace network configuration:"
echo "  IP Address    : ${IPV4}"
echo "  Prefix        : /${PREFIX_LEN}"
echo "  Network       : ${PREFIX_CIDR}"
echo "  Gateway       : ${GATEWAY}"
echo "  DNS           : ${DNS}"
echo
echo "============================================================"
echo
