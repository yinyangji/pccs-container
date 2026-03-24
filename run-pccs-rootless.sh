#!/usr/bin/env bash
set -euo pipefail

# 独立 PCCS 容器：
# - 依赖外部 AESMD 容器输出的 /var/run/aesmd/aesm.socket
# - 本脚本只启动 PCCS 容器

IMAGE_NAME="${IMAGE_NAME:-localhost/local/sgx-pccs-aesmd:ubuntu24.04}"
CONTAINER_NAME="${CONTAINER_NAME:-sgx-pccs}"
PCCS_PORT="${PCCS_PORT:-8081}"
AESMD_SOCKET_DIR="${AESMD_SOCKET_DIR:-${HOME}/.local/share/aesmd-shared}"
AESMD_SOCKET_PATH="${AESMD_SOCKET_DIR}/aesm.socket"
NETWORK_MODE="${NETWORK_MODE:-host}"
RESTART_POLICY="${RESTART_POLICY:-always}"
PCCS_MANUAL_INSTALL_MODE="${PCCS_MANUAL_INSTALL_MODE:-true}"

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

if [[ ! -d "${AESMD_SOCKET_DIR}" ]]; then
  echo "ERROR: AESMD socket directory not found: ${AESMD_SOCKET_DIR}"
  echo "Start AESMD container first (for example with ./run-aesm-rootless.sh)."
  exit 1
fi
if [[ ! -S "${AESMD_SOCKET_PATH}" ]]; then
  echo "ERROR: AESMD socket not found: ${AESMD_SOCKET_PATH}"
  echo "Ensure AESMD container is running and exporting aesm.socket."
  exit 1
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

echo "Starting PCCS container: ${CONTAINER_NAME}"
RUN_ARGS=(
  -d
  --name "${CONTAINER_NAME}"
  --network "${NETWORK_MODE}"
  --restart "${RESTART_POLICY}"
  --security-opt label=disable
  -v "${AESMD_SOCKET_DIR}:/var/run/aesmd:Z"
  -e PCCS_DEBUG_SHELL_ON_FAIL="${PCCS_DEBUG_SHELL_ON_FAIL:-true}"
  -e PCCS_PORT="${PCCS_PORT}"
  -e PCCS_HOST="${PCCS_HOST}"
  -e PCCS_API_KEY="${PCCS_API_KEY}"
  -e PCCS_ADMIN_PASSWORD="${PCCS_ADMIN_PASSWORD}"
  -e PCCS_USER_PASSWORD="${PCCS_USER_PASSWORD}"
  -e PCCS_PROXY="${PCCS_PROXY}"
  -e PCCS_REFRESH_SCHEDULE="${PCCS_REFRESH_SCHEDULE}"
  -e PCCS_LOG_LEVEL="${PCCS_LOG_LEVEL}"
  -e PCCS_USE_SECURE_CERT="${PCCS_USE_SECURE_CERT}"
)

if [[ "${PCCS_MANUAL_INSTALL_MODE}" == "true" ]]; then
  echo "PCCS_MANUAL_INSTALL_MODE=true: start container with idle shell for manual install."
  podman run "${RUN_ARGS[@]}" \
    --entrypoint /bin/bash \
    "${IMAGE_NAME}" \
    -lc 'echo "Container ready for manual PCCS install."; while true; do sleep 3600; done' >/dev/null
else
  podman run "${RUN_ARGS[@]}" \
    "${IMAGE_NAME}" >/dev/null
fi

echo "Container started. Check status with:"
echo "  podman ps --filter name=${CONTAINER_NAME}"
echo "  podman logs -f ${CONTAINER_NAME}"
echo "  podman exec -it ${CONTAINER_NAME} bash"
if [[ "${PCCS_MANUAL_INSTALL_MODE}" == "true" ]]; then
  echo "After manual installation, restart with:"
  echo "  PCCS_MANUAL_INSTALL_MODE=false ./run-pccs-rootless.sh"
fi
if [[ "${NETWORK_MODE}" != "host" ]]; then
  echo "NOTE: expose PCCS with -p ${PCCS_PORT}:${PCCS_PORT} when not using host network."
fi
