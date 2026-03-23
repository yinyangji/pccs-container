#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-local/sgx-pccs:ubuntu24.04}"
CONTAINER_NAME="${CONTAINER_NAME:-sgx-pccs}"
PCCS_PORT="${PCCS_PORT:-8081}"

# Required by Intel PCS when retrieving collaterals.
PCCS_API_KEY="${PCCS_API_KEY:-}"

# Optional runtime tuning.
PCCS_HOST="${PCCS_HOST:-0.0.0.0}"
PCCS_ADMIN_PASSWORD="${PCCS_ADMIN_PASSWORD:-PccsAdmin!234}"
PCCS_USER_PASSWORD="${PCCS_USER_PASSWORD:-PccsUser!234}"
PCCS_PROXY="${PCCS_PROXY:-}"
PCCS_REFRESH_SCHEDULE="${PCCS_REFRESH_SCHEDULE:-0 */12 * * *}"
PCCS_LOG_LEVEL="${PCCS_LOG_LEVEL:-info}"
PCCS_USE_SECURE_CERT="${PCCS_USE_SECURE_CERT:-false}"

if [[ -z "${PCCS_API_KEY}" ]]; then
  echo "WARNING: PCCS_API_KEY is empty. PCCS may fail to fetch collateral from Intel PCS."
fi

if podman container exists "${CONTAINER_NAME}"; then
  echo "Removing existing container: ${CONTAINER_NAME}"
  podman rm -f "${CONTAINER_NAME}" >/dev/null
fi

echo "Starting rootless container: ${CONTAINER_NAME}"
podman run -d \
  --name "${CONTAINER_NAME}" \
  -p "${PCCS_PORT}:8081" \
  --security-opt label=disable \
  -e PCCS_PORT=8081 \
  -e PCCS_HOST="${PCCS_HOST}" \
  -e PCCS_API_KEY="${PCCS_API_KEY}" \
  -e PCCS_ADMIN_PASSWORD="${PCCS_ADMIN_PASSWORD}" \
  -e PCCS_USER_PASSWORD="${PCCS_USER_PASSWORD}" \
  -e PCCS_PROXY="${PCCS_PROXY}" \
  -e PCCS_REFRESH_SCHEDULE="${PCCS_REFRESH_SCHEDULE}" \
  -e PCCS_LOG_LEVEL="${PCCS_LOG_LEVEL}" \
  -e PCCS_USE_SECURE_CERT="${PCCS_USE_SECURE_CERT}" \
  "${IMAGE_NAME}"

echo "Container started. Check status with:"
echo "  podman ps --filter name=${CONTAINER_NAME}"
echo "  podman logs -f ${CONTAINER_NAME}"
