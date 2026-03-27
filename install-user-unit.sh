#!/usr/bin/env bash
set -euo pipefail

UNIT_DIR="${HOME}/.config/systemd/user"
ENV_DIR="${HOME}/.config/sgx-pccs"
AESM_ENV_FILE="${ENV_DIR}/aesm.env"
PCCS_ENV_FILE="${ENV_DIR}/pccs.env"
AESM_UNIT_FILE="${UNIT_DIR}/sgx-aesm.service"
PCCS_UNIT_FILE="${UNIT_DIR}/sgx-pccs.service"

mkdir -p "${UNIT_DIR}" "${ENV_DIR}"

if [[ ! -f "${AESM_ENV_FILE}" ]]; then
  cat > "${AESM_ENV_FILE}" <<EOF
# AESM runtime options
AESM_IMAGE=localhost/sgx_aesm:latest
AESM_CONTAINER_NAME=aesm-service
# Shared AESM socket dir for cross-user access
AESMD_SOCKET_DIR=${HOME}/aesmd-shared
# Allow only this group to access the shared dir/socket.
# Set to an existing group on host (example: users / sgx).
AESMD_SHARED_GROUP=users
EOF
  echo "Created environment file: ${AESM_ENV_FILE}"
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
  echo "Created environment file: ${PCCS_ENV_FILE}"
fi

# Backward compatibility: add new keys if old env files already exist.
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

cat > "${AESM_UNIT_FILE}" <<'EOF'
[Unit]
Description=SGX AESM container (rootless Podman)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/sgx-pccs/aesm.env
ExecStartPre=-/usr/bin/podman rm -f ${AESM_CONTAINER_NAME}
ExecStartPre=/usr/bin/bash -lc 'socket_dir="${AESMD_SOCKET_DIR//%h/$HOME}"; mkdir -p "${socket_dir}" && chgrp "${AESMD_SHARED_GROUP}" "${socket_dir}" && chmod 2770 "${socket_dir}" && (command -v setfacl >/dev/null 2>&1 && setfacl -m "d:g:${AESMD_SHARED_GROUP}:rwx,g:${AESMD_SHARED_GROUP}:rwx" "${socket_dir}" || true)'
ExecStart=/usr/bin/bash -lc '/usr/bin/podman run --rm --name "${AESM_CONTAINER_NAME}" --security-opt label=disable --group-add keep-groups --device /dev/sgx_enclave --device /dev/sgx_provision $( [[ -e /dev/sgx_vepc ]] && echo "--device /dev/sgx_vepc" ) -v /dev/log:/dev/log -v "${AESMD_SOCKET_DIR}:/var/run/aesmd:Z" "${AESM_IMAGE}"'
ExecStop=-/usr/bin/podman stop -t 10 ${AESM_CONTAINER_NAME}
Restart=always
RestartSec=3
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF

cat > "${PCCS_UNIT_FILE}" <<'EOF'
[Unit]
Description=SGX PCCS container (rootless Podman)
Wants=network-online.target sgx-aesm.service
After=network-online.target sgx-aesm.service
Requires=sgx-aesm.service

[Service]
Type=simple
EnvironmentFile=%h/.config/sgx-pccs/pccs.env
ExecStartPre=-/usr/bin/podman rm -f ${PCCS_CONTAINER_NAME}
ExecStartPre=/usr/bin/bash -lc 'socket_dir="${AESMD_SOCKET_DIR//%h/$HOME}"; mkdir -p "${socket_dir}" && chgrp "${AESMD_SHARED_GROUP}" "${socket_dir}" && chmod 2770 "${socket_dir}" && (command -v setfacl >/dev/null 2>&1 && setfacl -m "d:g:${AESMD_SHARED_GROUP}:rwx,g:${AESMD_SHARED_GROUP}:rwx" "${socket_dir}" || true)'
ExecStart=/usr/bin/bash -lc '/usr/bin/podman run --rm --name "${PCCS_CONTAINER_NAME}" --network host --security-opt label=disable --group-add keep-groups --device /dev/sgx_enclave --device /dev/sgx_provision $( [[ -e /dev/sgx_vepc ]] && echo "--device /dev/sgx_vepc" ) -v "${AESMD_SOCKET_DIR}:/var/run/aesmd:Z" -e PCCS_PORT="${PCCS_PORT}" -e PCCS_HOST="${PCCS_HOST}" -e PCCS_API_KEY="${PCCS_API_KEY}" -e PCCS_ADMIN_PASSWORD="${PCCS_ADMIN_PASSWORD}" -e PCCS_USER_PASSWORD="${PCCS_USER_PASSWORD}" -e PCCS_PROXY="${PCCS_PROXY}" -e PCCS_REFRESH_SCHEDULE="${PCCS_REFRESH_SCHEDULE}" -e PCCS_LOG_LEVEL="${PCCS_LOG_LEVEL}" -e PCCS_USE_SECURE_CERT="${PCCS_USE_SECURE_CERT}" "${PCCS_IMAGE}"'
ExecStop=-/usr/bin/podman stop -t 10 ${PCCS_CONTAINER_NAME}
Restart=always
RestartSec=3
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now sgx-aesm.service sgx-pccs.service

echo
echo "User units installed and started:"
echo "  - sgx-aesm.service"
echo "  - sgx-pccs.service"
echo
echo "Check status:"
echo "  systemctl --user status sgx-aesm.service"
echo "  systemctl --user status sgx-pccs.service"
echo
echo "To make these user units available BEFORE login, enable linger once (root needed):"
echo "  sudo loginctl enable-linger ${USER}"
echo "Then verify:"
echo "  loginctl show-user ${USER} -p Linger"
echo
echo "Edit runtime configs:"
echo "  ${AESM_ENV_FILE}"
echo "  ${PCCS_ENV_FILE}"
echo "After edits:"
echo "  systemctl --user restart sgx-aesm.service sgx-pccs.service"
echo
echo "Note:"
echo "  systemd --user units belong to one Linux account (${USER})."
echo "  For cross-user access: PCCS is exposed on host network (default 8081),"
echo "  and AESM socket is shared via ~/aesmd-shared with group-restricted ACL."
echo "  Ensure other users are in AESMD_SHARED_GROUP (default: users)."
echo "  If you need truly system-wide service management for all users, ask admin to deploy system units under /etc/systemd/system."
