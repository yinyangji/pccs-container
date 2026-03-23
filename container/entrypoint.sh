#!/usr/bin/env bash
set -euo pipefail

if [[ -d "/opt/intel/sgx-dcap-pccs" ]]; then
  PCCS_DIR="/opt/intel/sgx-dcap-pccs"
elif [[ -d "/opt/sgx-dcap/QuoteGeneration/pccs" ]]; then
  PCCS_DIR="/opt/sgx-dcap/QuoteGeneration/pccs"
else
  echo "ERROR: PCCS installation directory not found."
  exit 1
fi

PCCS_CONFIG="${PCCS_DIR}/config/default.json"
PCCS_TEMPLATE="${PCCS_DIR}/config/default.json.template"

mkdir -p "${PCCS_DIR}/config"

if [[ ! -f "${PCCS_CONFIG}" && -f "${PCCS_TEMPLATE}" ]]; then
  cp "${PCCS_TEMPLATE}" "${PCCS_CONFIG}"
fi

if [[ ! -f "${PCCS_CONFIG}" ]]; then
  echo "ERROR: PCCS config file not found: ${PCCS_CONFIG}"
  exit 1
fi

: "${PCCS_PORT:=8081}"
: "${PCCS_HOST:=0.0.0.0}"
: "${PCCS_ADMIN_PASSWORD:=PccsAdmin!234}"
: "${PCCS_USER_PASSWORD:=PccsUser!234}"
: "${PCCS_API_KEY:=}"
: "${PCCS_PROXY:=}"
: "${PCCS_REFRESH_SCHEDULE:=0 */12 * * *}"
: "${PCCS_LOG_LEVEL:=info}"
: "${PCCS_USE_SECURE_CERT:=false}"

# Render key runtime parameters into config.
tmp_file="$(mktemp)"
jq \
  --argjson HTTPS_PORT "${PCCS_PORT}" \
  --arg HOST "${PCCS_HOST}" \
  --arg ADMIN_TOKEN "${PCCS_ADMIN_PASSWORD}" \
  --arg USER_TOKEN "${PCCS_USER_PASSWORD}" \
  --arg API_KEY "${PCCS_API_KEY}" \
  --arg PROXY "${PCCS_PROXY}" \
  --arg REFRESH_SCHEDULE "${PCCS_REFRESH_SCHEDULE}" \
  --arg LOG_LEVEL "${PCCS_LOG_LEVEL}" \
  --argjson USE_SECURE_CERT "$( [[ "${PCCS_USE_SECURE_CERT}" == "true" ]] && echo "true" || echo "false" )" \
  '
  .HTTPS_PORT = $HTTPS_PORT
  | .hosts = $HOST
  | .AdminToken = $ADMIN_TOKEN
  | .UserToken = $USER_TOKEN
  | .ApiKey = $API_KEY
  | .proxy = $PROXY
  | .RefreshSchedule = $REFRESH_SCHEDULE
  | .loglevel = $LOG_LEVEL
  | .use_secure_cert = $USE_SECURE_CERT
  ' "${PCCS_CONFIG}" > "${tmp_file}"
mv "${tmp_file}" "${PCCS_CONFIG}"

cd "${PCCS_DIR}"

echo "Starting PCCS on ${PCCS_HOST}:${PCCS_PORT}"
exec node pccs_server.js
