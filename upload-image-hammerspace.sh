#!/usr/bin/env bash

set -euo pipefail

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------

PROJECT_ID="c487a3ae-4569-4251-b81a-3241413edaf8"
REGION="eu01"

# Only change this for a new Hammerspace image
IMAGE_FILE="hammerspace-5.2.14-1267.qcow2"

# Automatically derived from filename
IMAGE_NAME="$(basename "${IMAGE_FILE}" .qcow2)"

DISK_FORMAT="qcow2"

API_URL="https://iaas.api.${REGION}.stackit.cloud/v1/projects/${PROJECT_ID}"

# ----------------------------------------------------------------------
# Tool checks
# ----------------------------------------------------------------------

command -v stackit >/dev/null 2>&1 || {
    echo "ERROR: stackit CLI not found."
    exit 1
}

command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq not found."
    exit 1
}

command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl not found."
    exit 1
}

# ----------------------------------------------------------------------
# Image file check
# ----------------------------------------------------------------------

if [[ ! -f "${IMAGE_FILE}" ]]; then
    echo "ERROR: Image file not found:"
    echo "       ${IMAGE_FILE}"
    exit 1
fi

echo "Image file:"
ls -lh "${IMAGE_FILE}"
echo

echo "Image name:"
echo "${IMAGE_NAME}"
echo

# Show QCOW2 information if qemu-img is available
if command -v qemu-img >/dev/null 2>&1; then
    echo "QCOW2 image information:"
    qemu-img info "${IMAGE_FILE}"
    echo
fi

# ----------------------------------------------------------------------
# Check STACKIT authentication and existing images
# ----------------------------------------------------------------------

echo "Checking STACKIT authentication and image access..."

if ! IMAGE_LIST="$(stackit image list 2>&1)"; then
    echo
    echo "ERROR: Unable to access STACKIT image service."
    echo
    echo "${IMAGE_LIST}"
    exit 1
fi

echo "Authentication OK."
echo

# Show existing Hammerspace images
HAMMERSPACE_IMAGES="$(
    printf '%s\n' "${IMAGE_LIST}" |
    grep -i "hammerspace" || true
)"

if [[ -n "${HAMMERSPACE_IMAGES}" ]]; then
    echo "Existing Hammerspace images:"
    echo "${HAMMERSPACE_IMAGES}"
    echo
else
    echo "No existing Hammerspace images found."
    echo
fi

# Avoid accidentally creating the same image again
if printf '%s\n' "${IMAGE_LIST}" | grep -Fqi "${IMAGE_NAME}"; then
    echo "ERROR: Image '${IMAGE_NAME}' already exists in STACKIT."
    echo "       Delete/rename the existing image or change IMAGE_FILE."
    exit 1
fi

# ----------------------------------------------------------------------
# Create image object
# ----------------------------------------------------------------------

echo "Creating STACKIT image object..."

RESPONSE="$(
    stackit curl \
        -X POST \
        -H "Content-Type: application/json" \
        --data "{
            \"active\": true,
            \"diskFormat\": \"${DISK_FORMAT}\",
            \"name\": \"${IMAGE_NAME}\"
        }" \
        "${API_URL}/images"
)"

IMAGE_ID="$(jq -r '.id // empty' <<<"${RESPONSE}")"
UPLOAD_URL="$(jq -r '.uploadUrl // empty' <<<"${RESPONSE}")"

if [[ -z "${IMAGE_ID}" || -z "${UPLOAD_URL}" ]]; then
    echo
    echo "ERROR: STACKIT did not return an image ID or upload URL."
    echo
    echo "${RESPONSE}" | jq .
    exit 1
fi

echo
echo "Image object created."
echo "Image ID: ${IMAGE_ID}"
echo

# ----------------------------------------------------------------------
# Upload QCOW2
# ----------------------------------------------------------------------

echo "Uploading ${IMAGE_FILE}..."
echo

if ! curl \
    --fail \
    --show-error \
    --location \
    --progress-bar \
    -X PUT \
    -H "Content-Type: binary/octet-stream" \
    --upload-file "${IMAGE_FILE}" \
    "${UPLOAD_URL}"
then
    echo
    echo "ERROR: Upload failed."
    echo "Image object may still exist:"
    echo "Image ID: ${IMAGE_ID}"
    exit 1
fi

echo
echo "Upload completed."
echo

# ----------------------------------------------------------------------
# Wait for image import
# ----------------------------------------------------------------------

echo "Waiting for STACKIT image import..."
echo

while true; do

    DETAILS="$(
        stackit curl \
            "${API_URL}/images/${IMAGE_ID}"
    )"

    STATUS="$(jq -r '.status // "UNKNOWN"' <<<"${DETAILS}")"

    printf '%s  Image state: %s\n' \
        "$(date '+%H:%M:%S')" \
        "${STATUS}"

    case "${STATUS}" in

        AVAILABLE)
            echo
            echo "Image successfully imported."
            echo "Image name: ${IMAGE_NAME}"
            echo "Image ID:   ${IMAGE_ID}"
            echo

            # Display final image information
            stackit image list | grep -i "${IMAGE_NAME}" || true

            exit 0
            ;;

        ERROR|FAILED)
            echo
            echo "ERROR: Image import failed."
            echo
            echo "Image details:"
            echo "${DETAILS}" | jq .
            exit 1
            ;;

        *)
            sleep 10
            ;;
    esac

done
