#!/usr/bin/env bash
# =============================================================================
#  scripts/stop.sh
#  -------------------------------------------------------------------
#  Stop ollama, the nanobot gateway, and the keep-alive loop cleanly.
#  Safe to run multiple times.
# =============================================================================
set -u
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INSTALL_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
PID_DIR="${INSTALL_ROOT}/run"

stop_pid() {
  local name="$1" pidfile="${PID_DIR}/${1}.pid"
  if [[ -f "$pidfile" ]]; then
    local pid
    pid="$(cat "$pidfile")"
    if kill -0 "$pid" 2>/dev/null; then
      printf "stopping %-12s (pid=%s) … " "$name" "$pid"
      kill "$pid" 2>/dev/null || true
      # Wait up to 10s for graceful exit, then SIGKILL
      for _ in {1..10}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
        printf "killed\n"
      else
        printf "ok\n"
      fi
    else
      printf "%-12s: not running (stale pidfile)\n" "$name"
    fi
    rm -f "$pidfile"
  else
    printf "%-12s: no pidfile\n" "$name"
  fi
}

stop_pid keepalive
stop_pid nanobot
stop_pid ollama
