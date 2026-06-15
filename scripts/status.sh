#!/usr/bin/env bash
# scripts/status.sh
# Health check for the nanobot-vm-deploy stack.
# - Ollama running and model loaded
# - nanobot gateway running and reachable
# - WebSocket channel reachable
# - Config values look sane
set -Eeuo pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=lib/logging.sh
. "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck source=lib/os-detect.sh
. "${SCRIPT_DIR}/lib/os-detect.sh"
# shellcheck source=lib/system.sh
. "${SCRIPT_DIR}/lib/system.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: sudo $0 [--help]

Checks that the nanobot-vm-deploy stack is installed and healthy:
  - ollama service + API + model present
  - nanobot-gateway service + REST /health + WebSocket port

Exit code is 0 if everything is green, 1 if anything is red.
EOF
  exit 0
fi

detect_os

ENV_FILE="/etc/nanobot/nanobot.env"
[[ -f "$ENV_FILE" ]] || die "env file not found at ${ENV_FILE} — has install.sh been run?"

# shellcheck disable=SC1090
. "$ENV_FILE"

PASS=0; FAIL=0
check() {
  local label="$1" status="$2"
  if [[ "$status" == "ok" ]]; then
    ok    "$label"
    PASS=$((PASS+1))
  else
    warn  "$label"
    FAIL=$((FAIL+1))
  fi
}

hdr "nanobot-vm-deploy :: status"

# ---- ollama ----
section "ollama"
if command -v ollama >/dev/null 2>&1; then
  note "version:  $(ollama --version 2>/dev/null || echo unknown)"
  if service_active ollama.service; then check "service ollama is active" ok
  else                                    check "service ollama is active" fail; fi
  if curl -sf "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    check "ollama API responds on ${OLLAMA_HOST}" ok
    note "models: $(curl -s "http://${OLLAMA_HOST}/api/tags" | jq -r '.models[].name' | tr '\n' ' ')"
  else
    check "ollama API responds on ${OLLAMA_HOST}" fail
  fi
else
  check "ollama binary present" fail
fi

# ---- nanobot ----
section "nanobot"
NANOBOT_BIN="/opt/nanobot/venv/bin/nanobot"
if [[ -x "$NANOBOT_BIN" ]]; then
  check "nanobot binary present (${NANOBOT_BIN})" ok
  note "version:  $("$NANOBOT_BIN" --version 2>/dev/null || echo unknown)"
else
  check "nanobot binary present" fail
fi

if service_active nanobot-gateway.service; then check "service nanobot-gateway is active" ok
else                                            check "service nanobot-gateway is active" fail; fi

# Gateway health
GW_URL="http://127.0.0.1:${NANOBOT_GATEWAY_PORT}/health"
if curl -sf --max-time 3 "$GW_URL" >/dev/null 2>&1; then
  check "gateway health endpoint responds (${GW_URL})" ok
else
  check "gateway health endpoint responds (${GW_URL})" fail
fi

# WebUI / WebSocket
WUI_URL="http://127.0.0.1:${NANOBOT_WEBUI_PORT}/"
if curl -sf --max-time 3 -o /dev/null "$WUI_URL" 2>&1 \
   || curl -s  --max-time 3 -o /dev/null -w "%{http_code}" "$WUI_URL" 2>/dev/null | grep -qE "^(200|301|302|404)$"; then
  # 404 is also "socket open" — the bundled WebUI is a single-page app and
  # may not serve "/" depending on nanobot version.
  check "WebUI port ${NANOBOT_WEBUI_PORT} accepts connections" ok
else
  check "WebUI port ${NANOBOT_WEBUI_PORT} accepts connections" fail
fi

# ---- config sanity ----
section "config"
if [[ -r "$NANOBOT_CFG" ]]; then
  check "config.json readable (${NANOBOT_CFG})" ok
  if jq -e '.channels.websocket.enabled' "$NANOBOT_CFG" >/dev/null; then
    if [[ "$(jq -r '.channels.websocket.enabled' "$NANOBOT_CFG")" == "true" ]]; then
      check "websocket channel enabled in config" ok
    else
      check "websocket channel enabled in config" fail
    fi
  fi
  if [[ -n "${NANOBOT_TOKEN_SECRET:-}" ]]; then
    check "tokenIssueSecret present (len=${#NANOBOT_TOKEN_SECRET})" ok
  else
    warn "NANOBOT_TOKEN_SECRET not exported from env file"
    check "tokenIssueSecret present" fail
  fi
else
  check "config.json readable" fail
fi

# ---- summary ----
hdr "summary"
echo "  ${C_GREEN}pass: ${PASS}${C_RESET}    ${C_RED}fail: ${FAIL}${C_RESET}"
echo
if [[ $FAIL -gt 0 ]]; then
  warn "Some checks failed. Recent gateway logs:"
  echo "------------------------------------------------------------"
  journalctl -u nanobot-gateway -n 30 --no-pager 2>/dev/null || true
  echo "------------------------------------------------------------"
  exit 1
fi
ok "everything looks healthy"
