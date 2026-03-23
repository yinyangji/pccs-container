#!/usr/bin/env bash
set -euo pipefail

PCCS_DEBUG_SHELL_ON_FAIL="${PCCS_DEBUG_SHELL_ON_FAIL:-true}"

on_error() {
  local rc="$?"
  echo "PCCS entrypoint failed with exit code ${rc}."
  if [[ "${PCCS_DEBUG_SHELL_ON_FAIL}" == "true" ]]; then
    echo "Entering debug shell due to startup failure."
    if [[ -x /bin/bash ]]; then
      exec /bin/bash -l
    else
      exec /bin/sh -l
    fi
  fi
  exit "${rc}"
}

trap on_error ERR

if [[ -d "/opt/intel/sgx-dcap-pccs" ]]; then
  PCCS_DIR="/opt/intel/sgx-dcap-pccs"
elif [[ -d "/opt/sgx-dcap/QuoteGeneration/pccs" ]]; then
  PCCS_DIR="/opt/sgx-dcap/QuoteGeneration/pccs"
else
  echo "ERROR: PCCS installation directory not found."
  if [[ "${PCCS_DEBUG_SHELL_ON_FAIL}" == "true" ]]; then
    echo "Entering debug shell because PCCS not installed yet."
    if [[ -x /bin/bash ]]; then
      exec /bin/bash -l
    else
      exec /bin/sh -l
    fi
  fi
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
  if [[ "${PCCS_DEBUG_SHELL_ON_FAIL}" == "true" ]]; then
    echo "Entering debug shell because PCCS config is missing."
    if [[ -x /bin/bash ]]; then
      exec /bin/bash -l
    else
      exec /bin/sh -l
    fi
  fi
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
set +e
node pccs_server.js
rc=$?
set -e

echo "PCCS server exited with code ${rc}."

# Ensure the container stays available for `podman exec ... bash` debugging.
# Default: keep a shell on failure; set `PCCS_DEBUG_SHELL_ON_FAIL=false` to exit instead.
PCCS_DEBUG_SHELL_ON_FAIL="${PCCS_DEBUG_SHELL_ON_FAIL:-true}"
if [[ "${PCCS_DEBUG_SHELL_ON_FAIL}" == "true" ]]; then
  echo "Entering debug shell because PCCS failed to stay running."
  if [[ -x /bin/bash ]]; then
    exec /bin/bash -l
  else
    exec /bin/sh -l
  fi
fi

exit "${rc}"
