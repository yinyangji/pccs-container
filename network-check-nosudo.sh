#!/usr/bin/env bash
set -u

# No-sudo network diagnostics with concise, human-readable output.

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

ok() { printf "${GREEN}[OK]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${RESET} %s\n" "$*"; }
info() { printf "${BLUE}[INFO]${RESET} %s\n" "$*"; }

HOSTS=("github.com" "www.baidu.com" "example.com")
IPS=("1.1.1.1" "8.8.8.8")
PORTS=(80 443)
CONNECT_TIMEOUT=3
HTTP_TIMEOUT=8

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

title() {
  printf "\n== %s ==\n" "$*"
}

dns_ok=0
tcp_ok=0
http_ok=0
gateway_ok=0
proxy_set=0

title "Environment"
info "Time: $(date '+%F %T %Z')"
info "User: $(whoami)"
info "Host: $(hostname)"

title "Proxy Variables"
proxy_dump="$(python3 - <<'PY'
import os
items = sorted((k, v) for k, v in os.environ.items() if "proxy" in k.lower())
for k, v in items:
    print(f"{k}={v}")
PY
)"
if [[ -n "${proxy_dump}" ]]; then
  proxy_set=1
  warn "Found proxy env vars:"
  printf "%s\n" "${proxy_dump}"
else
  ok "No proxy env vars in current shell"
fi

title "Routing"
if has_cmd ip; then
  default_route="$(ip route | awk '/^default/ {print; exit}')"
  if [[ -n "${default_route}" ]]; then
    ok "Default route: ${default_route}"
    gateway_ip="$(awk '/^default/ {print $3; exit}' <<<"${default_route}")"
    if [[ -n "${gateway_ip}" ]] && has_cmd ping; then
      if ping -c 2 -W 1 "${gateway_ip}" >/dev/null 2>&1; then
        gateway_ok=1
        ok "Gateway reachable: ${gateway_ip}"
      else
        fail "Gateway unreachable: ${gateway_ip}"
      fi
    fi
  else
    fail "No default route found"
  fi
else
  warn "'ip' command not found, skip route checks"
fi

title "DNS Resolution"
for host in "${HOSTS[@]}"; do
  if getent hosts "${host}" >/dev/null 2>&1; then
    resolved="$(getent hosts "${host}" | awk '{print $1}' | paste -sd ',' -)"
    ok "${host} -> ${resolved}"
    dns_ok=1
  else
    fail "DNS lookup failed: ${host}"
  fi
done

title "TCP Connectivity (no sudo)"
for ip in "${IPS[@]}"; do
  for port in "${PORTS[@]}"; do
    if timeout "${CONNECT_TIMEOUT}" bash -lc "echo > /dev/tcp/${ip}/${port}" >/dev/null 2>&1; then
      ok "${ip}:${port} connect success"
      tcp_ok=1
    else
      warn "${ip}:${port} connect failed"
    fi
  done
done

title "HTTP/HTTPS Probe"
if has_cmd curl; then
  for url in "http://example.com" "https://example.com" "https://github.com"; do
    if curl -4 -I --max-time "${HTTP_TIMEOUT}" "${url}" >/dev/null 2>&1; then
      ok "Reachable: ${url}"
      http_ok=1
    else
      warn "Timeout/failed: ${url}"
    fi
  done
else
  warn "'curl' command not found, skip HTTP checks"
fi

title "Diagnosis Summary"
if [[ "${dns_ok}" -eq 0 ]]; then
  fail "DNS is failing in this environment."
elif [[ "${gateway_ok}" -eq 1 && "${tcp_ok}" -eq 0 && "${http_ok}" -eq 0 ]]; then
  fail "LAN works, but outbound TCP/HTTP appears blocked by policy/firewall/VPN path."
elif [[ "${dns_ok}" -eq 1 && "${tcp_ok}" -eq 1 && "${http_ok}" -eq 0 ]]; then
  warn "TCP works but HTTP fails: likely proxy/TLS filtering/application-layer policy."
elif [[ "${http_ok}" -eq 1 ]]; then
  ok "Internet connectivity appears healthy."
else
  warn "Partial connectivity detected; check route, proxy, and upstream policy."
fi

if [[ "${proxy_set}" -eq 1 ]]; then
  info "Proxy env vars are present. If unreachable, verify proxy server address and ACL."
else
  info "No shell proxy env vars detected."
fi

info "Done. This script used no sudo."
