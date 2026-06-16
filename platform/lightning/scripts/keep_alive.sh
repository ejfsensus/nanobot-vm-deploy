#!/usr/bin/env bash
# =============================================================================
#  scripts/keep_alive.sh
#  -------------------------------------------------------------------
#  Three jobs:
#    1. Pings the WebUI every 2 minutes so the Studio doesn't auto-sleep
#       after 10 minutes of "inactivity". (Anything the Studio sees as
#       activity counts — including this loop.)
#    2. Watches the nanobot + ollama PIDs and restarts them if they die.
#    3. Tails its own log so you can see what it's doing.
#
#  Run it once via on_start.sh (that's the normal path) or manually with
#      nohup ./scripts/keep_alive.sh &> logs/keepalive.log &
#  Stop it cleanly with:
#      kill $(cat run/keepalive.pid)
# =============================================================================
set -u

# ---- paths ----
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INSTALL_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
ENV_FILE="${INSTALL_ROOT}/nanobot.env"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

LOG_DIR="${INSTALL_ROOT}/logs"
PID_DIR="${INSTALL_ROOT}/run"
mkdir -p "$LOG_DIR" "$PID_DIR"

# Write our own PID (overwritten by on_start.sh but that's fine)
echo $$ > "${PID_DIR}/keepalive.pid"

PING_INTERVAL="${KEEPALIVE_PING_INTERVAL:-120}"   # seconds
GATEWAY_URL="http://${NANOBOT_WEBUI_HOST:-127.0.0.1}:${NANOBOT_WEBUI_PORT:-8765}/"
HEALTH_URL="http://${NANOBOT_WEBUI_HOST:-127.0.0.1}:${NANOBOT_GATEWAY_PORT:-18790}/health"
OLLAMA_URL="http://${OLLAMA_HOST:-127.0.0.1:11434}/api/tags"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { printf '[%s] %s\n' "$(ts)" "$*"; }
warn() { printf '[%s] [!] %s\n' "$(ts)" "$*" >&2; }

trap 'log "keep_alive.sh exiting (signal)"; rm -f "${PID_DIR}/keepalive.pid"; exit 0' INT TERM

log "keep_alive.sh started (pid=$$)"
log "ping every ${PING_INTERVAL}s: ${GATEWAY_URL}"

iteration=0
while true; do
  iteration=$((iteration+1))

  # ---- 1. Activity ping (keeps Studio awake) ----
  # 2xx/3xx/404 all mean "the port is open and someone is listening".
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$GATEWAY_URL" 2>/dev/null || echo "000")
  if [[ "$code" =~ ^(200|301|302|404|401)$ ]]; then
    [[ $((iteration % 5)) -eq 0 ]] && log "ping #${iteration}: HTTP ${code} (studio is active)"
  else
    warn "ping #${iteration}: HTTP ${code} — gateway not responding on ${GATEWAY_URL}"
  fi

  # ---- 2. Watchdog: nanobot gateway ----
  if [[ -f "${PID_DIR}/nanobot.pid" ]]; then
    pid="$(cat "${PID_DIR}/nanobot.pid")"
    if ! kill -0 "$pid" 2>/dev/null; then
      warn "nanobot gateway (pid=${pid}) is dead — restarting"
      if [[ -x "${NANOBOT_BIN}" ]]; then
        cd "$INSTALL_ROOT" || true
        nohup "${NANOBOT_BIN}" gateway >> "${LOG_DIR}/nanobot.log" 2>&1 &
        echo $! > "${PID_DIR}/nanobot.pid"
        log "nanobot gateway restarted (pid=$!)"
      else
        warn "NANOBOT_BIN=${NANOBOT_BIN} not executable — cannot restart"
      fi
    fi
  fi

  # ---- 3. Watchdog: ollama ----
  if ! curl -sf --max-time 3 "$OLLAMA_URL" >/dev/null 2>&1; then
    warn "ollama not responding on ${OLLAMA_URL} — restarting"
    if command -v ollama >/dev/null 2>&1; then
      nohup ollama serve >> "${LOG_DIR}/ollama.log" 2>&1 &
      # Best-effort PID capture (race with other ollama processes)
      sleep 2
      pgrep -f "ollama serve" | head -1 > "${PID_DIR}/ollama.pid" 2>/dev/null || true
      log "ollama restart issued"
    fi
  fi

  sleep "$PING_INTERVAL"
done
