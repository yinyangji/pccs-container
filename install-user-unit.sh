#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-sgx-pccs.service}"
UNIT_DIR="${HOME}/.config/systemd/user"
ENV_DIR="${HOME}/.config/sgx-pccs"
ENV_FILE="${ENV_DIR}/pccs.env"
UNIT_FILE="${UNIT_DIR}/${SERVICE_NAME}"

mkdir -p "${UNIT_DIR}" "${ENV_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" <<'EOF'
# Intel PCS API Key (required in production)
PCCS_API_KEY=

# Runtime options
IMAGE_NAME=local/sgx-pccs:ubuntu24.04
CONTAINER_NAME=sgx-pccs
PCCS_PORT=8081
PCCS_HOST=0.0.0.0
PCCS_ADMIN_PASSWORD=PccsAdmin!234
PCCS_USER_PASSWORD=PccsUser!234
PCCS_PROXY=
PCCS_REFRESH_SCHEDULE=0 */12 * * *
PCCS_LOG_LEVEL=info
PCCS_USE_SECURE_CERT=false
EOF
  echo "Created environment file: ${ENV_FILE}"
fi

cat > "${UNIT_FILE}" <<'EOF'
[Unit]
Description=SGX PCCS container (rootless Podman)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/sgx-pccs/pccs.env
ExecStartPre=/usr/bin/podman rm -f ${CONTAINER_NAME}
ExecStart=/usr/bin/podman run --rm --name ${CONTAINER_NAME} -p ${PCCS_PORT}:8081 --security-opt label=disable -e PCCS_PORT=8081 -e PCCS_HOST=${PCCS_HOST} -e PCCS_API_KEY=${PCCS_API_KEY} -e PCCS_ADMIN_PASSWORD=${PCCS_ADMIN_PASSWORD} -e PCCS_USER_PASSWORD=${PCCS_USER_PASSWORD} -e PCCS_PROXY=${PCCS_PROXY} -e PCCS_REFRESH_SCHEDULE=${PCCS_REFRESH_SCHEDULE} -e PCCS_LOG_LEVEL=${PCCS_LOG_LEVEL} -e PCCS_USE_SECURE_CERT=${PCCS_USE_SECURE_CERT} ${IMAGE_NAME}
ExecStop=/usr/bin/podman stop -t 10 ${CONTAINER_NAME}
Restart=always
RestartSec=5
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now "${SERVICE_NAME}"

echo
echo "User unit installed and started: ${SERVICE_NAME}"
echo "Check status:"
echo "  systemctl --user status ${SERVICE_NAME}"
echo
echo "To make user unit available BEFORE login, enable linger once (root privilege needed):"
echo "  sudo loginctl enable-linger ${USER}"
echo
echo "Then verify:"
echo "  loginctl show-user ${USER} -p Linger"
echo
echo "Edit runtime config in:"
echo "  ${ENV_FILE}"
echo "After edits:"
echo "  systemctl --user restart ${SERVICE_NAME}"
