#!/usr/bin/env bash
# =============================================================================
#  platform/lightning/scripts/install.sh
#  -------------------------------------------------------------------
#  Initial installer for the Lightning.ai Studio variation.
#
#  Run this ONCE from a Studio terminal (the web terminal in the browser).
#  After it finishes:
#    * Ollama + nanobot are installed under /teamspace/studios/<this_studio>/
#    * The on-start hook is in place at .lightning_studio/on_start.sh
#    * The keep-alive loop will start on next launch
#
#  Re-running is safe — the script is idempotent.
#
#  Idempotent: re-run any time to refresh config, pull a new model,
#              re-link the on-start hook, etc.
# =============================================================================
set -Eeuo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INSTALL_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${INSTALL_ROOT}/../.." &> /dev/null && pwd )"

# ---------- sane defaults (override via .env) ----------
INSTALL_ROOT_DEFAULT="/teamspace/studios/${STUDIO_NAME:-nanobot}"
INSTALL_ROOT="${NANOBOT_INSTALL_ROOT:-$INSTALL_ROOT_DEFAULT}"

OLLAMA_MODEL="${OLLAMA_MODEL:-openbmb/minicpm5:latest}"
NANOBOT_MODEL_NAME="${NANOBOT_MODEL_NAME:-minicpm5:latest}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-8192}"
NANOBOT_WEBUI_HOST="${NANOBOT_WEBUI_HOST:-0.0.0.0}"     # bind to all so Port Viewer can reach
NANOBOT_WEBUI_PORT="${NANOBOT_WEBUI_PORT:-8765}"        # Lightning's Port Viewer is happy with this
NANOBOT_GATEWAY_HOST="${NANOBOT_GATEWAY_HOST:-127.0.0.1}"
NANOBOT_GATEWAY_PORT="${NANOBOT_GATEWAY_PORT:-18790}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
OLLAMA_MODELS="${OLLAMA_MODELS:-${INSTALL_ROOT}/ollama/models}"
OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"
OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-1}"
OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-10m}"
OLLAMA_FLASH_ATTENTION="${OLLAMA_FLASH_ATTENTION:-0}"   # CPU only on the free tier
KEEPALIVE_PING_INTERVAL="${KEEPALIVE_PING_INTERVAL:-120}"

# ---------- log helpers ----------
if [[ -t 1 ]]; then
  readonly C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
  readonly C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m' C_CYAN=$'\033[36m'
else
  readonly C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
fi
log()  { printf "%s[•]%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
ok()   { printf "%s[✓]%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf "%s[!]%s %s\n" "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf "%s[✗]%s %s\n" "$C_RED"    "$C_RESET" "$*" >&2; }
hdr()  { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }
note() { printf "  %s↳%s %s\n" "$C_DIM" "$C_RESET" "$*"; }

DRY_RUN="false"
SKIP_MODEL="false"
for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN="true" ;;
    --skip-model)  SKIP_MODEL="true" ;;
    -h|--help)
      sed -n '4,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
  esac
done
run() { if [[ "$DRY_RUN" == "true" ]]; then printf "  (dry-run) %s\n" "$*"; else "$@"; fi; }

# ---------- load .env if present ----------
if [[ -f "${REPO_ROOT}/.env" ]]; then
  log "loading ${REPO_ROOT}/.env"
  set -a; source "${REPO_ROOT}/.env"; set +a
fi
# Re-pick names that may have been overridden
INSTALL_ROOT="${NANOBOT_INSTALL_ROOT:-${INSTALL_ROOT:-${INSTALL_ROOT_DEFAULT}}}"

# ---------- preflight ----------
if [[ ! -d /teamspace ]]; then
  err "/teamspace not found — this installer is for Lightning AI Studios only."
  err "If you're on a regular VM, run the top-level ./install.sh instead."
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  err "python3 not found on PATH."
  exit 1
fi
PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "$(printf '%s\n%s' '3.11' "$PY_VER" | sort -V | head -1)" != "3.11" ]]; then
  err "nanobot needs Python 3.11+; found ${PY_VER}"
  exit 1
fi

hdr "nanobot-vm-deploy :: lightning.ai installer v${SCRIPT_VERSION}"
[[ "$DRY_RUN" == "true" ]] && warn "DRY RUN — no changes will be made"
note "INSTALL_ROOT = ${INSTALL_ROOT}"
note "STUDIO_NAME  = ${STUDIO_NAME:-<unset>}"
note "STUDIO_HOME  = ${HOME:-<unset>}"
note "model        = ${OLLAMA_MODEL}  (alias: ${NANOBOT_MODEL_NAME})"

# ---------- 1. directories ----------
hdr "Step 1 / 6 — Persistent directories"
run mkdir -p \
  "${INSTALL_ROOT}" \
  "${INSTALL_ROOT}/logs" \
  "${INSTALL_ROOT}/run" \
  "${INSTALL_ROOT}/venv" \
  "${OLLAMA_MODELS}"
ok "directories ready"

# ---------- 2. ollama ----------
hdr "Step 2 / 6 — Ollama"
if command -v ollama >/dev/null 2>&1; then
  note "ollama already installed:  $(ollama --version 2>/dev/null || echo unknown)"
else
  log "installing ollama via official installer"
  if [[ "$DRY_RUN" != "true" ]]; then
    # Lightning Studios are Ubuntu/Debian under the hood
    curl -fsSL https://ollama.com/install.sh | sh
  fi
  ok "ollama installed"
fi
ok "ollama env: OLLAMA_HOST=${OLLAMA_HOST}  OLLAMA_MODELS=${OLLAMA_MODELS}"

# ---------- 3. model ----------
if [[ "$SKIP_MODEL" == "true" ]]; then
  hdr "Step 3 / 6 — Model pull  (skipped via --skip-model)"
else
  hdr "Step 3 / 6 — Model: ${OLLAMA_MODEL}"
  # Start ollama transiently for the pull if it's not already running
  if [[ "$DRY_RUN" == "true" ]]; then
    note "(dry-run) would transient-start ollama for the model pull"
  else
    if ! curl -sf "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
      log "starting ollama transiently for pull"
      OLLAMA_HOST="${OLLAMA_HOST}" OLLAMA_MODELS="${OLLAMA_MODELS}" \
        nohup ollama serve >/dev/null 2>&1 &
      OLLAMA_PID=$!
      for i in {1..30}; do
        curl -sf "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1 && break
        sleep 1
      done
    fi
  fi
  # ollama list columns: NAME  ID  SIZE  MODIFIED
  if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$OLLAMA_MODEL" \
     || ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "${OLLAMA_MODEL%:*}"; then
    note "model '${OLLAMA_MODEL}' already pulled"
  else
    log "pulling ${OLLAMA_MODEL}"
    run ollama pull "$OLLAMA_MODEL"
  fi
  # Create the num_ctx alias
  alias_name="${NANOBOT_MODEL_NAME%:*}-ctx${OLLAMA_CONTEXT_LENGTH}"
  log "creating alias ${alias_name} (num_ctx=${OLLAMA_CONTEXT_LENGTH})"
  if [[ "$DRY_RUN" != "true" ]]; then
    cat > /tmp/Modelfile.nb <<EOF
FROM ${OLLAMA_MODEL}
PARAMETER num_ctx ${OLLAMA_CONTEXT_LENGTH}
EOF
    ollama rm  "$alias_name" >/dev/null 2>&1 || true
    ollama create "$alias_name" -f /tmp/Modelfile.nb
    rm -f /tmp/Modelfile.nb
    NANOBOT_MODEL_NAME="$alias_name"
    ok "alias ready: ${NANOBOT_MODEL_NAME}"
  fi
  # Stop the transient ollama so the on-start hook can start it cleanly
  if [[ -n "${OLLAMA_PID:-}" ]] && kill -0 "$OLLAMA_PID" 2>/dev/null; then
    kill "$OLLAMA_PID" 2>/dev/null || true
  fi
fi

# ---------- 4. nanobot venv ----------
hdr "Step 4 / 6 — nanobot"
NANOBOT_VENV="${INSTALL_ROOT}/venv"
NANOBOT_BIN="${NANOBOT_VENV}/bin/nanobot"
if [[ -x "$NANOBOT_BIN" ]]; then
  note "nanobot already installed:  $("$NANOBOT_BIN" --version 2>/dev/null || echo unknown)"
else
  log "creating venv at ${NANOBOT_VENV}"
  run python3 -m venv "${NANOBOT_VENV}"
  run "${NANOBOT_VENV}/bin/pip" install --upgrade pip wheel setuptools
  log "installing nanobot-ai (this is the big one — pulls ~40 deps)"
  run "${NANOBOT_VENV}/bin/pip" install nanobot-ai
  # Symlink for PATH convenience inside the Studio
  mkdir -p "${HOME}/.local/bin"
  run ln -sf "${NANOBOT_BIN}" "${HOME}/.local/bin/nanobot"
  ok "nanobot installed at ${NANOBOT_BIN}"
fi

# ---------- 5. config ----------
hdr "Step 5 / 6 — nanobot config"
NANOBOT_CFG_DIR="${INSTALL_ROOT}/.nanobot"
run mkdir -p "${NANOBOT_CFG_DIR}/workspace"

# Generate a strong token secret — required when WebUI binds to 0.0.0.0
SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"

log "writing ${NANOBOT_CFG_DIR}/config.json"
if [[ "$DRY_RUN" != "true" ]]; then
  cat > "${NANOBOT_CFG_DIR}/config.json" <<EOF
{
  "workspace": "${NANOBOT_CFG_DIR}/workspace",
  "providers": {
    "local": {
      "apiBase": "http://${OLLAMA_HOST}/v1",
      "apiKey": "ollama",
      "model": "${NANOBOT_MODEL_NAME}"
    }
  },
  "modelPresets": {
    "default": {
      "label": "Local Ollama",
      "provider": "local",
      "model": "${NANOBOT_MODEL_NAME}",
      "maxTokens": 4096,
      "contextWindowTokens": ${OLLAMA_CONTEXT_LENGTH},
      "temperature": 0.7
    }
  },
  "agents": {
    "defaults": {
      "modelPreset": "default",
      "maxTokens": 4096,
      "maxToolIterations": 20,
      "memoryWindow": 50
    }
  },
  "gateway": {
    "host": "${NANOBOT_GATEWAY_HOST}",
    "port": ${NANOBOT_GATEWAY_PORT}
  },
  "channels": {
    "websocket": {
      "enabled": true,
      "host": "${NANOBOT_WEBUI_HOST}",
      "port": ${NANOBOT_WEBUI_PORT},
      "tokenIssueSecret": "${SECRET}"
    }
  }
}
EOF
fi

log "writing ${INSTALL_ROOT}/nanobot.env"
if [[ "$DRY_RUN" != "true" ]]; then
  cat > "${INSTALL_ROOT}/nanobot.env" <<EOF
# Generated by platform/lightning/scripts/install.sh
NANOBOT_INSTALL_ROOT=${INSTALL_ROOT}
NANOBOT_VENV=${NANOBOT_VENV}
NANOBOT_BIN=${NANOBOT_BIN}
NANOBOT_CFG_DIR=${NANOBOT_CFG_DIR}
NANOBOT_GATEWAY_HOST=${NANOBOT_GATEWAY_HOST}
NANOBOT_GATEWAY_PORT=${NANOBOT_GATEWAY_PORT}
NANOBOT_WEBUI_HOST=${NANOBOT_WEBUI_HOST}
NANOBOT_WEBUI_PORT=${NANOBOT_WEBUI_PORT}
NANOBOT_TOKEN_SECRET=${SECRET}
NANOBOT_MODEL_NAME=${NANOBOT_MODEL_NAME}
OLLAMA_HOST=${OLLAMA_HOST}
OLLAMA_MODELS=${OLLAMA_MODELS}
OLLAMA_MODEL=${OLLAMA_MODEL}
OLLAMA_NUM_PARALLEL=${OLLAMA_NUM_PARALLEL}
OLLAMA_MAX_LOADED_MODELS=${OLLAMA_MAX_LOADED_MODELS}
OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE}
OLLAMA_FLASH_ATTENTION=${OLLAMA_FLASH_ATTENTION}
OLLAMA_CONTEXT_LENGTH=${OLLAMA_CONTEXT_LENGTH}
KEEPALIVE_PING_INTERVAL=${KEEPALIVE_PING_INTERVAL}
STUDIO_NAME=${STUDIO_NAME:-}
EOF
  chmod 0600 "${INSTALL_ROOT}/nanobot.env"
fi

# Make ollama aware of its model dir (for the next launch)
log "writing ${INSTALL_ROOT}/ollama.env"
if [[ "$DRY_RUN" != "true" ]]; then
  cat > "${INSTALL_ROOT}/ollama.env" <<EOF
OLLAMA_HOST=${OLLAMA_HOST}
OLLAMA_MODELS=${OLLAMA_MODELS}
OLLAMA_NUM_PARALLEL=${OLLAMA_NUM_PARALLEL}
OLLAMA_MAX_LOADED_MODELS=${OLLAMA_MAX_LOADED_MODELS}
OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE}
OLLAMA_FLASH_ATTENTION=${OLLAMA_FLASH_ATTENTION}
EOF
fi
ok "config written"

# ---------- 6. on-start hook ----------
hdr "Step 6 / 6 — On-start hook + .studiorc"

# Copy the bundled on_start.sh and keep_alive.sh into the install root
run mkdir -p "${INSTALL_ROOT}/.lightning_studio"
run cp "${REPO_ROOT}/platform/lightning/.lightning_studio/on_start.sh" \
       "${INSTALL_ROOT}/.lightning_studio/on_start.sh"
run chmod +x "${INSTALL_ROOT}/.lightning_studio/on_start.sh"

# Place the canonical keep_alive.sh next to the rest of our scripts
run cp "${REPO_ROOT}/platform/lightning/scripts/keep_alive.sh" \
       "${INSTALL_ROOT}/scripts/keep_alive.sh"
run chmod +x "${INSTALL_ROOT}/scripts/keep_alive.sh"

# Mirror the on_start.sh to the Studio's actual home so Lightning picks it up
STUDIO_ON_START="${HOME}/.lightning_studio/on_start.sh"
run mkdir -p "${HOME}/.lightning_studio"
run cp "${INSTALL_ROOT}/.lightning_studio/on_start.sh" "$STUDIO_ON_START"
run chmod +x "$STUDIO_ON_START"

# .studiorc — export env so manual commands Just Work
run cp "${REPO_ROOT}/platform/lightning/.lightning_studio/.studiorc" \
       "${HOME}/.lightning_studio/.studiorc"
if [[ "$DRY_RUN" != "true" ]]; then
  cat >> "${HOME}/.lightning_studio/.studiorc" <<EOF

# Source the install env so manual commands see the same paths
if [[ -f "${INSTALL_ROOT}/nanobot.env" ]]; then
  set -a
  source "${INSTALL_ROOT}/nanobot.env"
  set +a
fi
# Convenience: put the venv and nanobot on PATH
export PATH="${NANOBOT_VENV}/bin:\${HOME}/.local/bin:\${PATH}"
EOF
fi
ok "on-start hook and .studiorc in place"

# ---------- post-install hook (custom MCP / skills) ----------
if [[ -x "${REPO_ROOT}/scripts/post-install.sh" ]]; then
  hdr "post-install hook (shared scripts/post-install.sh)"
  if [[ "$DRY_RUN" != "true" ]]; then
    NANOBOT_CFG_DIR="${NANOBOT_CFG_DIR}" \
    NANOBOT_USER="${USER:-studio}" \
    NANOBOT_HOME="${INSTALL_ROOT}" \
    bash "${REPO_ROOT}/scripts/post-install.sh" || warn "post-install hook returned non-zero (continuing)"
  else
    note "(dry-run) would run ${REPO_ROOT}/scripts/post-install.sh"
  fi
fi

# ---------- final report ----------
if [[ "$DRY_RUN" != "true" ]]; then
  hdr "Install complete"
  cat <<EOF

  ${C_BOLD}nanobot:${C_RESET}       $("$NANOBOT_BIN" --version 2>/dev/null || echo 'installed')
  ${C_BOLD}ollama:${C_RESET}        $(ollama --version 2>/dev/null || echo 'installed')
  ${C_BOLD}model:${C_RESET}         ${NANOBOT_MODEL_NAME}  (from ${OLLAMA_MODEL})
  ${C_BOLD}install root:${C_RESET}  ${INSTALL_ROOT}
  ${C_BOLD}on-start hook:${C_RESET} ${STUDIO_ON_START}
  ${C_BOLD}config:${C_RESET}        ${NANOBOT_CFG_DIR}/config.json
  ${C_BOLD}env file:${C_RESET}      ${INSTALL_ROOT}/nanobot.env

  ${C_BOLD}── Logs (from a Studio terminal) ──${C_RESET}
  tail -f ${INSTALL_ROOT}/logs/on_start.log
  tail -f ${INSTALL_ROOT}/logs/ollama.log
  tail -f ${INSTALL_ROOT}/logs/nanobot.log
  tail -f ${INSTALL_ROOT}/logs/keepalive.log

  ${C_BOLD}── Bring up the stack NOW ──${C_RESET}
  bash ${INSTALL_ROOT}/scripts/start.sh

  ${C_BOLD}── Bring it down cleanly ──${C_RESET}
  bash ${INSTALL_ROOT}/scripts/stop.sh

  ${C_BOLD}── Health check ──${C_RESET}
  bash ${INSTALL_ROOT}/scripts/status.sh

  ${C_BOLD}── Expose the WebUI publicly ──${C_RESET}
  1. Open the Lightning Studio in your browser
  2. Click the plug-ins icon (top right)  →  "Port viewer"
  3. Add port  ${NANOBOT_WEBUI_PORT}     ← the WebUI
     Add port  ${NANOBOT_GATEWAY_PORT}   ← gateway /health
  4. Click "Open" next to each — Lightning prints a public URL.
  5. The WebUI URL is what you share with people.

  ${C_BOLD}── IMPORTANT ──${C_RESET}
  • The on-start hook runs every time the Studio launches (incl. after sleep
    and after a forced restart).  You don't need to do anything after the
    initial install — open the WebUI via Port Viewer and go.
  • Don't put state in /tmp or /root — those are wiped between sessions.
    Everything is under ${INSTALL_ROOT} which is on /teamspace.
  • To change the model: edit ${REPO_ROOT}/.env, then re-run this installer.

EOF
fi
