#!/usr/bin/env bash
set -euo pipefail

# 独立 PCCS 容器：
# - 依赖外部 AESMD 容器输出的 /var/run/aesmd/aesm.socket
# - 本脚本只启动 PCCS 容器

IMAGE_NAME="${IMAGE_NAME:-localhost/local/sgx-pccs-aesmd:ubuntu24.04}"
CONTAINER_NAME="${CONTAINER_NAME:-sgx-pccs}"
PCCS_PORT="${PCCS_PORT:-8081}"
# AESMD socket 暴露给其它容器的方式：通过 podman named volume。
AESMD_SOCKET_VOLUME="${AESMD_SOCKET_VOLUME:-aesmd-socket}"
NETWORK_MODE="${NETWORK_MODE:-host}"
RESTART_POLICY="${RESTART_POLICY:-always}"
PCCS_MANUAL_INSTALL_MODE="${PCCS_MANUAL_INSTALL_MODE:-true}"

# 将宿主机项目目录映射到容器中（默认映射到你当前用户的 ~/projects）
# 通过 :U 尽量让 rootless 场景下的容器内用户获得读写权限。
PROJECTS_HOST_DIR="${PROJECTS_HOST_DIR:-${HOME}/projects}"
PROJECTS_CONTAINER_DIR="${PROJECTS_CONTAINER_DIR:-/root/projects}"
PROJECTS_MOUNT_OPTS="${PROJECTS_MOUNT_OPTS:-Z,U}"

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

if [[ ! -d "${PROJECTS_HOST_DIR}" ]]; then
  echo "ERROR: projects dir not found: ${PROJECTS_HOST_DIR}"
  exit 1
fi

if ! podman volume exists "${AESMD_SOCKET_VOLUME}" >/dev/null 2>&1; then
  echo "ERROR: podman named volume not found: ${AESMD_SOCKET_VOLUME}"
  echo "Start AESMD first (same named volume: ${AESMD_SOCKET_VOLUME}). See README: 启动 AESMD（aesm-service）。"
  exit 1
fi

echo "Using AESMD socket volume: ${AESMD_SOCKET_VOLUME} (/var/run/aesmd in container)"

AESMD_SOCKET_MOUNT_ARGS=(-v "${AESMD_SOCKET_VOLUME}:/var/run/aesmd:Z")

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

RUN_DEVICES=(
  --device /dev/sgx_enclave:/dev/sgx_enclave
  --device /dev/sgx_provision:/dev/sgx_provision
)
if [[ -e /dev/sgx_vepc ]]; then
  RUN_DEVICES+=(--device /dev/sgx_vepc:/dev/sgx_vepc)
fi

echo "Starting PCCS container: ${CONTAINER_NAME}"
RUN_ARGS=(
  -d
  --name "${CONTAINER_NAME}"
  --network "${NETWORK_MODE}"
  --restart "${RESTART_POLICY}"
  --security-opt label=disable
  --group-add keep-groups
  -v "${PROJECTS_HOST_DIR}:${PROJECTS_CONTAINER_DIR}:${PROJECTS_MOUNT_OPTS}"
  "${RUN_DEVICES[@]}"
  "${AESMD_SOCKET_MOUNT_ARGS[@]}"
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
    -lc 'install -d /run/systemd/system; echo "Container ready for manual PCCS install (see /usr/local/bin/pccs-apt-prep.sh if apt configure fails)."; while true; do sleep 3600; done' >/dev/null
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
