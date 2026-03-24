#!/usr/bin/env bash
set -euo pipefail

# Rootless AESMD container launcher.
# Exposes aesm.socket via a host directory so other containers can reuse it.

IMAGE_NAME="${IMAGE_NAME:-ghcr.io/oasisprotocol/aesmd-dcap:master}"
CONTAINER_NAME="${CONTAINER_NAME:-aesmd}"
RESTART_POLICY="${RESTART_POLICY:-always}"
AESMD_SOCKET_DIR="${AESMD_SOCKET_DIR:-${HOME}/.local/share/aesmd-shared}"
AESMD_SOCKET_PATH="${AESMD_SOCKET_DIR}/aesm.socket"

if ! podman image exists "${IMAGE_NAME}"; then
  echo "ERROR: image not found locally: ${IMAGE_NAME}"
  echo "Pull it first:"
  echo "  podman pull ${IMAGE_NAME}"
  exit 1
fi

for dev in /dev/sgx_enclave /dev/sgx_provision; do
  if [[ ! -e "${dev}" ]]; then
    echo "ERROR: required SGX device is missing: ${dev}"
    echo "Check host SGX driver/device setup before starting AESMD."
    exit 1
  fi
done

if [[ ! -d "${AESMD_SOCKET_DIR}" ]]; then
  echo "Creating shared AESMD socket directory: ${AESMD_SOCKET_DIR}"
  mkdir -p "${AESMD_SOCKET_DIR}"
fi
chmod 1777 "${AESMD_SOCKET_DIR}"

if podman container exists "${CONTAINER_NAME}"; then
  echo "Removing existing container: ${CONTAINER_NAME}"
  podman rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "Starting AESMD container: ${CONTAINER_NAME}"
podman run --detach \
  --name "${CONTAINER_NAME}" \
  --restart "${RESTART_POLICY}" \
  --security-opt label=disable \
  --device /dev/sgx_enclave:/dev/sgx_enclave \
  --device /dev/sgx_provision:/dev/sgx_provision \
  --volume "${AESMD_SOCKET_DIR}:/var/run/aesmd:Z" \
  "${IMAGE_NAME}" >/dev/null

echo "Waiting for AESMD socket: ${AESMD_SOCKET_PATH}"
for _ in $(seq 1 20); do
  if [[ -S "${AESMD_SOCKET_PATH}" ]]; then
    echo "AESMD is ready: ${AESMD_SOCKET_PATH}"
    break
  fi
  sleep 1
done

if [[ ! -S "${AESMD_SOCKET_PATH}" ]]; then
  echo "WARNING: socket not found yet: ${AESMD_SOCKET_PATH}"
  echo "Inspect container logs:"
  echo "  podman logs --tail=200 ${CONTAINER_NAME}"
fi

echo "AESMD container started. Useful commands:"
echo "  podman ps --filter name=${CONTAINER_NAME}"
echo "  podman logs -f ${CONTAINER_NAME}"
echo "  ls -l ${AESMD_SOCKET_DIR}"