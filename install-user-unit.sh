#!/usr/bin/env bash
# User systemd 单元：install = 部署仓库内已修复模板；remove = 卸载以免与手动 podman 冲突。
set -euo pipefail

ROOT=$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")
TEMPLATE_DIR="${ROOT}/systemd/user"
UNIT_DIR="${HOME}/.config/systemd/user"
ENV_DIR="${HOME}/.config/sgx-pccs"
AESM_ENV_FILE="${ENV_DIR}/aesm.env"
PCCS_ENV_FILE="${ENV_DIR}/pccs.env"
AESM_UNIT="${UNIT_DIR}/sgx-aesm.service"
PCCS_UNIT="${UNIT_DIR}/sgx-pccs.service"

usage() {
  cat <<EOF
usage: $(basename "$0") <install|remove>

  install   从 ${TEMPLATE_DIR}/ 复制已修复的 sgx-*.service（ExecStartPre 无 bash \${VAR//}，避免 journal 里
            socket_dir / AESMD_SOCKET_DIR///... 误报）。创建或修正 ~/.config/sgx-pccs/*.env。
            不自动 enable/start；需要时：systemctl --user enable --now sgx-aesm.service

  remove    停止并删除 user 单元，daemon-reload
EOF
  exit 1
}

# 修正曾被 systemd 与错误单元行弄乱的 AESMD_SOCKET_DIR（含 \$HOME、///、多行重复等）
sanitize_aesmd_socket_in_env() {
  local f=$1
  [[ -f "$f" ]] || return 0
  local n
  n=$(grep -c '^AESMD_SOCKET_DIR=' "$f" 2>/dev/null) || true
  n=${n:-0}
  if [[ "${n}" -gt 1 ]]; then
    cp "$f" "${f}.bak.dedup"
    grep -v '^AESMD_SOCKET_DIR=' "$f" > "${f}.tmp.$$"
    echo "AESMD_SOCKET_DIR=${HOME}/aesmd-shared" >> "${f}.tmp.$$"
    mv "${f}.tmp.$$" "$f"
    echo "已去重并写入 AESMD_SOCKET_DIR=${HOME}/aesmd-shared（备份 ${f}.bak.dedup）" >&2
    return 0
  fi
  if grep -q '^AESMD_SOCKET_DIR=' "$f" && grep '^AESMD_SOCKET_DIR=' "$f" | grep -qE '\$|///'; then
    cp "$f" "${f}.bak.sanitize"
    grep -v '^AESMD_SOCKET_DIR=' "$f" > "${f}.tmp.$$"
    mv "${f}.tmp.$$" "$f"
    echo "AESMD_SOCKET_DIR=${HOME}/aesmd-shared" >> "$f"
    echo "已修正 $f 中异常的 AESMD_SOCKET_DIR（备份 ${f}.bak.sanitize）" >&2
  fi
}

do_install() {
  mkdir -p "${UNIT_DIR}" "${ENV_DIR}"

  if [[ ! -f "${AESM_ENV_FILE}" ]]; then
    cat > "${AESM_ENV_FILE}" <<EOF
# AESM runtime options
AESM_IMAGE=localhost/sgx_aesm:latest
AESM_CONTAINER_NAME=aesm-service
AESMD_SOCKET_DIR=${HOME}/aesmd-shared
AESMD_SHARED_GROUP=users
EOF
    echo "已创建 ${AESM_ENV_FILE}"
  fi

  if [[ ! -f "${PCCS_ENV_FILE}" ]]; then
    cat > "${PCCS_ENV_FILE}" <<EOF
# PCCS runtime options
PCCS_IMAGE=localhost/local/sgx-pccs-aesmd:ubuntu24.04
PCCS_CONTAINER_NAME=sgx-pccs
AESMD_SOCKET_DIR=${HOME}/aesmd-shared
AESMD_SHARED_GROUP=users
PCCS_PORT=8081
PCCS_HOST=0.0.0.0
PCCS_API_KEY=
PCCS_ADMIN_PASSWORD=PccsAdmin!234
PCCS_USER_PASSWORD=PccsUser!234
PCCS_PROXY=
PCCS_REFRESH_SCHEDULE=0 */12 * * *
PCCS_LOG_LEVEL=info
PCCS_USE_SECURE_CERT=false
EOF
    echo "已创建 ${PCCS_ENV_FILE}"
  fi

  if ! grep -q '^AESMD_SOCKET_DIR=' "${AESM_ENV_FILE}"; then
    echo "AESMD_SOCKET_DIR=${HOME}/aesmd-shared" >> "${AESM_ENV_FILE}"
  fi
  if ! grep -q '^AESMD_SHARED_GROUP=' "${AESM_ENV_FILE}"; then
    echo 'AESMD_SHARED_GROUP=users' >> "${AESM_ENV_FILE}"
  fi
  if ! grep -q '^AESMD_SOCKET_DIR=' "${PCCS_ENV_FILE}"; then
    echo "AESMD_SOCKET_DIR=${HOME}/aesmd-shared" >> "${PCCS_ENV_FILE}"
  fi
  if ! grep -q '^AESMD_SHARED_GROUP=' "${PCCS_ENV_FILE}"; then
    echo 'AESMD_SHARED_GROUP=users' >> "${PCCS_ENV_FILE}"
  fi

  sanitize_aesmd_socket_in_env "${AESM_ENV_FILE}"
  sanitize_aesmd_socket_in_env "${PCCS_ENV_FILE}"

  cp -f "${TEMPLATE_DIR}/sgx-aesm.service" "${AESM_UNIT}"
  cp -f "${TEMPLATE_DIR}/sgx-pccs.service" "${PCCS_UNIT}"

  if systemctl --user is-system-running &>/dev/null; then
    systemctl --user daemon-reload
  fi

  echo "已安装单元：${AESM_UNIT}、${PCCS_UNIT}"
  echo "未执行 enable/start。需要自启时：systemctl --user enable --now sgx-aesm.service sgx-pccs.service"
}

do_remove() {
  if systemctl --user is-system-running &>/dev/null; then
    systemctl --user disable --now sgx-pccs.service 2>/dev/null || true
    systemctl --user disable --now sgx-aesm.service 2>/dev/null || true
  fi

  rm -f "${PCCS_UNIT}" "${AESM_UNIT}"

  if systemctl --user is-system-running &>/dev/null; then
    systemctl --user daemon-reload
  fi

  echo "已移除 user 单元：sgx-pccs.service、sgx-aesm.service（未删 ~/.config/sgx-pccs/*.env）"
}

case "${1:-}" in
  install) do_install ;;
  remove) do_remove ;;
  *) usage ;;
esac
