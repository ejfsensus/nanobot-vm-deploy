#!/usr/bin/env bash
# =============================================================================
#  .lightning_studio/on_start.sh
#  -------------------------------------------------------------------
#  Lightning AI Studio runs this script every time the Studio launches —
#  including the first start, every wake-from-sleep, and every restart.
#  It must be idempotent and survive partial installs.
#
#  Responsibilities:
#    1. Locate the persistent install (under /teamspace/studios/<this_studio>)
#    2. Source /teamspace/.../nanobot.env so the rest of the script sees our config
#    3. Start Ollama (idempotent: skip if already running)
#    4. Start the nanobot gateway (idempotent)
#    5. Start the keep-alive loop (idempotent)
#    6. Print a friendly status block
# =============================================================================
set -u
# NOTE: do NOT set -e — we want to keep going through the sleep/wake cycle
# even if one step hiccups.

# ---------- paths ----------
# Studio home is the directory this script lives in. Lightning sets CWD
# to the studio home when invoking on_start.sh, so $HOME is the studio root.
STUDIO_HOME="${HOME:-$(pwd)}"
INSTALL_ROOT="/teamspace/studios/${STUDIO_NAME:-$(basename "$STUDIO_HOME")}"
if [[ ! -d "$INSTALL_ROOT" ]]; then
  # Fallback: derive from the script path
  INSTALL_ROOT="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/../.." &> /dev/null && pwd )"
fi

ENV_FILE="${INSTALL_ROOT}/nanobot.env"
LOG_DIR="${INSTALL_ROOT}/logs"
PID_DIR="${INSTALL_ROOT}/run"
mkdir -p "$LOG_DIR" "$PID_DIR"

# ---------- logging ----------
ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { printf '[%s] [•] %s\n' "$(ts)" "$*"; }
ok()   { printf '[%s] [✓] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] [!] %s\n' "$(ts)" "$*" >&2; }
err()  { printf '[%s] [✗] %s\n' "$(ts)" "$*" >&2; }
hdr()  { printf '\n[%s] == %s ==\n' "$(ts)" "$*"; }

# Redirect everything to a rolling log so users can `tail -f` it from a
# second terminal or read it after the fact.
exec >> "${LOG_DIR}/on_start.log" 2>&1

hdr "on_start.sh :: nanobot-vm-deploy (lightning.ai variation)"
log "STUDIO_HOME=${STUDIO_HOME}"
log "INSTALL_ROOT=${INSTALL_ROOT}"
log "STUDIO_NAME=${STUDIO_NAME:-<unset>}"
log "USER=${USER:-<unset>}"
log "PATH=${PATH}"

# ---------- source env ----------
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
  ok "loaded env from ${ENV_FILE}"
else
  warn "no env file at ${ENV_FILE} — first run? Run scripts/install.sh once via the Studio terminal."
fi

# ---------- 1. ollama ----------
start_ollama() {
  if [[ -f "${PID_DIR}/ollama.pid" ]] \
     && kill -0 "$(cat "${PID_DIR}/ollama.pid")" 2>/dev/null; then
    log "ollama already running (pid $(cat "${PID_DIR}/ollama.pid"))"
    return 0
  fi
  if ! command -v ollama >/dev/null 2>&1; then
    err "ollama binary not found on PATH — has scripts/install.sh been run?"
    return 1
  fi
  log "starting ollama serve"
  nohup ollama serve >> "${LOG_DIR}/ollama.log" 2>&1 &
  echo $! > "${PID_DIR}/ollama.pid"
  # Wait for it to bind
  local ollama_host="${OLLAMA_HOST:-127.0.0.1:11434}"
  for i in {1..30}; do
    if curl -sf "http://${ollama_host}/api/tags" >/dev/null 2>&1; then
      ok "ollama up on ${ollama_host}"
      return 0
    fi
    sleep 1
  done
  warn "ollama did not respond within 30s — check ${LOG_DIR}/ollama.log"
}

# ---------- 2. nanobot gateway ----------
start_gateway() {
  if [[ -f "${PID_DIR}/nanobot.pid" ]] \
     && kill -0 "$(cat "${PID_DIR}/nanobot.pid")" 2>/dev/null; then
    log "nanobot gateway already running (pid $(cat "${PID_DIR}/nanobot.pid"))"
    return 0
  fi
  if [[ ! -x "${NANOBOT_BIN:-/opt/nanobot/venv/bin/nanobot}" ]]; then
    err "nanobot binary not found at ${NANOBOT_BIN:-/opt/nanobot/venv/bin/nanobot} — install.sh not run?"
    return 1
  fi
  log "starting nanobot gateway"
  cd "${INSTALL_ROOT}" || true
  nohup "${NANOBOT_BIN}" gateway \
        >> "${LOG_DIR}/nanobot.log" 2>&1 &
  echo $! > "${PID_DIR}/nanobot.pid"
  # Wait for it to bind the WebUI port
  local host="${NANOBOT_WEBUI_HOST:-127.0.0.1}"
  local port="${NANOBOT_WEBUI_PORT:-8765}"
  for i in {1..30}; do
    if curl -sf -o /dev/null "http://${host}:${port}/" 2>/dev/null \
       || curl -s  -o /dev/null -w '%{http_code}' "http://${host}:${port}/" 2>/dev/null | grep -qE '^(200|301|302|404)$'; then
      ok "gateway up on ${host}:${port}"
      return 0
    fi
    sleep 1
  done
  warn "gateway did not bind within 30s — check ${LOG_DIR}/nanobot.log"
}

# ---------- 3. keep-alive ----------
start_keepalive() {
  if [[ -f "${PID_DIR}/keepalive.pid" ]] \
     && kill -0 "$(cat "${PID_DIR}/keepalive.pid")" 2>/dev/null; then
    log "keep-alive already running (pid $(cat "${PID_DIR}/keepalive.pid"))"
    return 0
  fi
  local ka="${INSTALL_ROOT}/scripts/keep_alive.sh"
  if [[ ! -x "$ka" ]]; then
    warn "no keep_alive.sh at ${ka} — skipping (studio may idle-sleep after 10 min)"
    return 0
  fi
  log "starting keep_alive.sh"
  nohup "$ka" >> "${LOG_DIR}/keepalive.log" 2>&1 &
  echo $! > "${PID_DIR}/keepalive.pid"
  ok "keep-alive running (pid $(cat "${PID_DIR}/keepalive.pid"))"
}

# ---------- run ----------
start_ollama
start_gateway
start_keepalive

# ---------- final report ----------
hdr "on_start.sh done"
{
  echo "  WebUI (inside studio):  http://${NANOBOT_WEBUI_HOST:-127.0.0.1}:${NANOBOT_WEBUI_PORT:-8765}/"
  echo "  Public URL:             open the Port Viewer plugin and click 'Open' on port ${NANOBOT_WEBUI_PORT:-8765}"
  echo "  Gateway health:         http://${NANOBOT_WEBUI_HOST:-127.0.0.1}:${NANOBOT_GATEWAY_PORT:-18790}/health"
  echo "  Ollama API:             http://${OLLAMA_HOST:-127.0.0.1:11434}"
  echo "  Model:                  ${NANOBOT_MODEL_NAME:-<unset>}"
  echo "  Logs:                   tail -f ${LOG_DIR}/{ollama,nanobot,keepalive}.log"
  echo "  Status:                 ${INSTALL_ROOT}/scripts/status.sh"
} | tee -a "${LOG_DIR}/on_start.log"
