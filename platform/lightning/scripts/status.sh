#!/usr/bin/env bash
# =============================================================================
#  scripts/status.sh
#  -------------------------------------------------------------------
#  Lightning-specific health check:
#    - ollama + model
#    - nanobot gateway + WebUI port
#    - keep-alive loop
#    - persistence paths
#    - on_start.sh hook presence
# =============================================================================
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INSTALL_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

ENV_FILE="${INSTALL_ROOT}/nanobot.env"
[[ -f "$ENV_FILE" ]] || { echo "[!] ${ENV_FILE} missing — has scripts/install.sh been run?"; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

if [[ -t 1 ]]; then
  readonly C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
  readonly C_RED=$'\033[31m'   C_GREEN=$'\033[32m'  C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m'
else
  readonly C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
fi

PASS=0; FAIL=0
ok()   { printf "%s[✓]%s %s\n" "$C_GREEN" "$C_RESET" "$*"; PASS=$((PASS+1)); }
bad()  { printf "%s[✗]%s %s\n" "$C_RED"   "$C_RESET" "$*"; FAIL=$((FAIL+1)); }
note() { printf "  %s↳%s %s\n"  "$C_DIM"   "$C_RESET" "$*"; }
hdr()  { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_BLUE" "$*" "$C_RESET"; }

PID_DIR="${INSTALL_ROOT}/run"
LOG_DIR="${INSTALL_ROOT}/logs"
ON_START="${INSTALL_ROOT}/.lightning_studio/on_start.sh"

hdr "nanobot-vm-deploy :: lightning.ai status"
echo "  install root:  ${INSTALL_ROOT}"
echo "  studio name:   ${STUDIO_NAME:-<unset>}"
echo "  model:         ${NANOBOT_MODEL_NAME:-<unset>}  (from ${OLLAMA_MODEL:-<unset>})"

# ---- persistence ----
hdr "persistence"
for d in "$INSTALL_ROOT" "$LOG_DIR" "$PID_DIR" "${OLLAMA_MODELS:-/root/.ollama/models}"; do
  if [[ -d "$d" ]]; then
    note "exists: $d"
  else
    bad "missing: $d"
  fi
done
if mountpoint -q /teamspace 2>/dev/null; then
  ok "/teamspace is a persistent mount"
else
  bad "/teamspace is NOT a persistent mount — your install will be lost on restart!"
fi

# ---- on_start.sh hook ----
hdr "on-start hook"
if [[ -x "$ON_START" ]]; then
  ok "on_start.sh present and executable"
else
  bad "on_start.sh missing or not executable at ${ON_START}"
fi

# ---- processes ----
hdr "processes"
for svc in keepalive nanobot ollama; do
  pidf="${PID_DIR}/${svc}.pid"
  if [[ -f "$pidf" ]] && kill -0 "$(cat "$pidf")" 2>/dev/null; then
    ok "${svc} running (pid $(cat "$pidf"))"
  else
    bad "${svc} not running"
  fi
done

# ---- network ----
hdr "network"
OLLAMA_URL="http://${OLLAMA_HOST:-127.0.0.1:11434}/api/tags"
if curl -sf --max-time 3 "$OLLAMA_URL" >/dev/null 2>&1; then
  ok "ollama API responds on ${OLLAMA_URL}"
  models=$(curl -s "$OLLAMA_URL" | python3 -c 'import sys,json; print(" ".join(m["name"] for m in json.load(sys.stdin).get("models",[])))' 2>/dev/null || true)
  [[ -n "$models" ]] && note "models: $models" || note "(no models parsed — jq/python missing?)"
else
  bad "ollama API does not respond on ${OLLAMA_URL}"
fi

GW_URL="http://${NANOBOT_WEBUI_HOST:-127.0.0.1}:${NANOBOT_WEBUI_PORT:-8765}/"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$GW_URL" 2>/dev/null || echo 000)
if [[ "$code" =~ ^(200|301|302|404|401)$ ]]; then
  ok "WebUI port responds (HTTP ${code} on ${GW_URL})"
  note "open with: lightning Port Viewer plugin → port ${NANOBOT_WEBUI_PORT:-8765}"
else
  bad "WebUI port not responding (HTTP ${code} on ${GW_URL})"
fi

HEALTH_URL="http://${NANOBOT_WEBUI_HOST:-127.0.0.1}:${NANOBOT_GATEWAY_PORT:-18790}/health"
if curl -sf --max-time 3 "$HEALTH_URL" >/dev/null 2>&1; then
  ok "gateway /health responds (${HEALTH_URL})"
else
  bad "gateway /health does not respond (${HEALTH_URL})"
fi

# ---- summary ----
hdr "summary"
echo "  ${C_GREEN}pass: ${PASS}${C_RESET}    ${C_RED}fail: ${FAIL}${C_RESET}"
echo
if [[ $FAIL -gt 0 ]]; then
  printf "${C_YELLOW}recent logs:${C_RESET}\n"
  echo "------------------------------------------------------------"
  for f in on_start ollama nanobot keepalive; do
    [[ -f "${LOG_DIR}/${f}.log" ]] && { echo "--- ${f}.log (last 20) ---"; tail -20 "${LOG_DIR}/${f}.log"; }
  done
  echo "------------------------------------------------------------"
  exit 1
fi
printf "${C_GREEN}all green${C_RESET}\n"
