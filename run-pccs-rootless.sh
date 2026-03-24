#!/usr/bin/env bash
set -euo pipefail

# 单容器架构：
# - pccs + aesmd 运行在同一个容器
# - 映射 SGX 设备到该容器

IMAGE_NAME="${IMAGE_NAME:-localhost/local/sgx-pccs-aesmd:ubuntu24.04}"
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

if ! podman image exists "${IMAGE_NAME}"; then
  echo "ERROR: image not found locally: ${IMAGE_NAME}"
  echo "Build it first with:"
  echo "  ./build-image.sh"
  echo "Or load it manually with:"
  echo "  podman load -i <image.tar>"
  exit 1
fi

if podman container exists "${CONTAINER_NAME}"; then
  echo "Removing existing container: ${CONTAINER_NAME}"
  podman rm -f "${CONTAINER_NAME}" >/dev/null
fi

DEV_ARGS=()
for dev in /dev/sgx_enclave /dev/sgx_provision /dev/sgx_vepc; do
  if [[ -e "${dev}" ]]; then
    DEV_ARGS+=(--device "${dev}:${dev}")
  else
    echo "WARNING: device not found on host: ${dev}"
  fi
done

echo "Starting single-container pccs+aesmd: ${CONTAINER_NAME}"
podman run -d \
  --name "${CONTAINER_NAME}" \
  --network host \
  --security-opt label=disable \
  "${DEV_ARGS[@]}" \
  --entrypoint /bin/bash \
  -e PCCS_PORT=8081 \
  -e PCCS_HOST="${PCCS_HOST}" \
  -e PCCS_API_KEY="${PCCS_API_KEY}" \
  -e PCCS_ADMIN_PASSWORD="${PCCS_ADMIN_PASSWORD}" \
  -e PCCS_USER_PASSWORD="${PCCS_USER_PASSWORD}" \
  -e PCCS_PROXY="${PCCS_PROXY}" \
  -e PCCS_REFRESH_SCHEDULE="${PCCS_REFRESH_SCHEDULE}" \
  -e PCCS_LOG_LEVEL="${PCCS_LOG_LEVEL}" \
  -e PCCS_USE_SECURE_CERT="${PCCS_USE_SECURE_CERT}" \
  "${IMAGE_NAME}" \
  -lc '
set -e
mkdir -p /var/run/aesmd
if [[ -x /opt/intel/sgx-aesm-service/aesm/aesm_service ]]; then
  /opt/intel/sgx-aesm-service/aesm/aesm_service --no-daemon &
else
  echo "INFO: AESMD binary not found. Install it inside container when needed."
fi
if [[ -f /opt/intel/sgx-dcap-pccs/pccs_server.js ]]; then
  cd /opt/intel/sgx-dcap-pccs
  node pccs_server.js &
else
  echo "INFO: PCCS not installed yet. Install/configure it inside container."
fi
while true; do sleep 3600; done
'

echo "Container started. Check status with:"
echo "  podman ps --filter name=${CONTAINER_NAME}"
echo "  podman logs -f ${CONTAINER_NAME}"
