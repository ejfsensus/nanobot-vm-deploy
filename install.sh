#!/usr/bin/env bash
# =============================================================================
#  nanobot-vm-deploy :: bootstrap installer
#  -------------------------------------------------------------------
#  Provisions a brand-new Linux VM with:
#    * nanobot (HKUDS) — AI agent runtime + bundled WebUI
#    * Ollama            — local model server
#    * Configured model  — defaults to openbmb/minicpm5:latest
#    * systemd services  — auto-start on boot
#
#  Usage:
#    # 1. Recommended: clone the repo and run from inside it
#    git clone <your-repo-url> ~/nanobot-vm-deploy
#    cd ~/nanobot-vm-deploy
#    cp .env.example .env       # then edit if you want a different model/etc
#    sudo ./install.sh
#
#    # 2. One-liner (no clone) — uses baked-in defaults
#    curl -fsSL https://raw.githubusercontent.com/<you>/nanobot-vm-deploy/main/install.sh | sudo bash
#
#    # 3. Re-run / update: safe — the script is idempotent
#    sudo ./install.sh
#
#  Flags:
#    --dry-run        Show what would be done, change nothing
#    --skip-model     Don't pull the Ollama model (useful on slow links)
#    --skip-ollama    Don't install/manage Ollama (you run it yourself)
#    --user <name>    Override the system user nanobot runs as (default: nanobot)
#    --help           Show usage
# =============================================================================
set -Eeuo pipefail

# -----------------------------------------------------------------------------
#  Constants & defaults — everything overridable via env or .env file
# -----------------------------------------------------------------------------
readonly SCRIPT_VERSION="1.0.0"
readonly NANOBOT_PKG="nanobot-ai"           # PyPI package
readonly NANOBOT_MIN_PYTHON="3.11"
readonly NANOBOT_USER="${NANOBOT_USER:-nanobot}"
readonly NANOBOT_HOME="/var/lib/${NANOBOT_USER}"
readonly NANOBOT_VENV="/opt/nanobot/venv"
readonly NANOBOT_BIN="${NANOBOT_VENV}/bin/nanobot"
readonly NANOBOT_CFG_DIR="${NANOBOT_HOME}/.nanobot"
readonly NANOBOT_CFG="${NANOBOT_CFG_DIR}/config.json"
readonly NANOBOT_ENV_FILE="/etc/nanobot/nanobot.env"
readonly OLLAMA_ENV_FILE="/etc/nanobot/ollama.env"
readonly NANOBOT_SERVICE="/etc/systemd/system/nanobot-gateway.service"
readonly OLLAMA_SERVICE="/etc/systemd/system/ollama.service"

# Defaults — overridden by .env (next to install.sh) if present
NANOBOT_GATEWAY_HOST="${NANOBOT_GATEWAY_HOST:-0.0.0.0}"
NANOBOT_GATEWAY_PORT="${NANOBOT_GATEWAY_PORT:-18790}"
NANOBOT_WEBUI_HOST="${NANOBOT_WEBUI_HOST:-0.0.0.0}"
NANOBOT_WEBUI_PORT="${NANOBOT_WEBUI_PORT:-8765}"
OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
OLLAMA_MODELS_DIR="${OLLAMA_MODELS_DIR:-/var/lib/ollama/models}"
OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"
OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-1}"
OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-10m}"
OLLAMA_FLASH_ATTENTION="${OLLAMA_FLASH_ATTENTION:-1}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-8192}"

# Model — the only thing you usually change
# On Ollama: openbmb/minicpm5:latest  →  in nanobot config: minicpm5:latest
# (Ollama's OpenAI-compatible API strips the namespace)
OLLAMA_MODEL="${OLLAMA_MODEL:-openbmb/minicpm5:latest}"
NANOBOT_MODEL_NAME="${NANOBOT_MODEL_NAME:-minicpm5:latest}"

# Behaviour flags
DRY_RUN="false"
SKIP_MODEL="false"
SKIP_OLLAMA="false"
SCRIPT_DIR=""

# -----------------------------------------------------------------------------
#  Tiny logger (kept inline so install.sh works even when piped via curl)
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_BOLD=$'\033[1m'
  readonly C_DIM=$'\033[2m'
  readonly C_RED=$'\033[31m'
  readonly C_GREEN=$'\033[32m'
  readonly C_YELLOW=$'\033[33m'
  readonly C_BLUE=$'\033[34m'
  readonly C_CYAN=$'\033[36m'
else
  readonly C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
fi

log()    { printf "%s[•]%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
ok()     { printf "%s[✓]%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
warn()   { printf "%s[!]%s %s\n" "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()    { printf "%s[✗]%s %s\n" "$C_RED"    "$C_RESET" "$*" >&2; }
hdr()    { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }
section(){ printf "\n%s%s── %s ──%s\n" "$C_BOLD" "$C_DIM" "$*" "$C_RESET"; }
note()   { printf "  %s↳%s %s\n" "$C_DIM" "$C_RESET" "$*"; }

run() {
  # run <cmd...> — honours DRY_RUN
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "  %s(dry-run)%s %s\n" "$C_DIM" "$C_RESET" "$*"
  else
    "$@"
  fi
}

# -----------------------------------------------------------------------------
#  Argument parsing
# -----------------------------------------------------------------------------
usage() {
  sed -n '4,28p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN="true"; shift ;;
    --skip-model)   SKIP_MODEL="true"; shift ;;
    --skip-ollama)  SKIP_OLLAMA="true"; shift ;;
    --user)         NANOBOT_USER="$2"; shift 2 ;;
    --user=*)       NANOBOT_USER="${1#*=}"; shift ;;
    -h|--help)      usage ;;
    *)              err "Unknown flag: $1"; usage ;;
  esac
done

# -----------------------------------------------------------------------------
#  Load .env if present (next to install.sh) — only after arg parsing
# -----------------------------------------------------------------------------
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  log "Loading ${SCRIPT_DIR}/.env"
  # shellcheck disable=SC1090,SC1091
  set -a; source "${SCRIPT_DIR}/.env"; set +a
  # Re-pick up env-overridable names that may have changed
  NANOBOT_GATEWAY_HOST="${NANOBOT_GATEWAY_HOST:-0.0.0.0}"
  NANOBOT_GATEWAY_PORT="${NANOBOT_GATEWAY_PORT:-18790}"
  NANOBOT_WEBUI_HOST="${NANOBOT_WEBUI_HOST:-0.0.0.0}"
  NANOBOT_WEBUI_PORT="${NANOBOT_WEBUI_PORT:-8765}"
  OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
  OLLAMA_MODELS_DIR="${OLLAMA_MODELS_DIR:-/var/lib/ollama/models}"
  OLLAMA_MODEL="${OLLAMA_MODEL:-openbmb/minicpm5:latest}"
  NANOBOT_MODEL_NAME="${NANOBOT_MODEL_NAME:-minicpm5:latest}"
fi

# -----------------------------------------------------------------------------
#  Preflight
# -----------------------------------------------------------------------------
require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "This installer must be run as root (or with sudo)."
    err "Re-run:  sudo $0 $*"
    exit 1
  fi
}

detect_os() {
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"
  OS_VERSION="${VERSION_ID:-}"
  case "$OS_ID" in
    ubuntu|debian|linuxmint|pop|elementary|zorin) PKG_MGR="apt" ;;
    rhel|centos|rocky|almalinux|ol|fedora|nobara) PKG_MGR="dnf" ;;
    fedora)                                        PKG_MGR="dnf" ;;
    arch|manjaro|endeavouros)                      PKG_MGR="pacman" ;;
    opensuse*|sles)                                PKG_MGR="zypper" ;;
    alpine)                                        PKG_MGR="apk" ;;
    *)                                             PKG_MGR="apt" ;;  # best-effort
  esac
  log "Detected OS: ${OS_ID} ${OS_VERSION}  (package manager: ${PKG_MGR})"
}

check_python() {
  if command -v python3 >/dev/null 2>&1; then
    local py; py="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    if [[ "$(printf '%s\n%s' "$NANOBOT_MIN_PYTHON" "$py" | sort -V | head -1)" == "$NANOBOT_MIN_PYTHON" ]]; then
      note "python3 ${py} ≥ ${NANOBOT_MIN_PYTHON}  ✓"
      PYTHON_BIN="$(command -v python3)"
      return
    fi
    warn "python3 ${py} is older than ${NANOBOT_MIN_PYTHON}; will install a newer one"
  fi
  install_python
}

# -----------------------------------------------------------------------------
#  Package install helpers
# -----------------------------------------------------------------------------
pkg_update() {
  case "$PKG_MGR" in
    apt)     run apt-get update -y ;;
    dnf)     run dnf -y makecache ;;
    pacman)  run pacman -Sy --noconfirm ;;
    zypper)  run zypper --non-interactive refresh ;;
    apk)     run apk update ;;
  esac
}

pkg_install() {
  case "$PKG_MGR" in
    apt)     run apt-get install -y --no-install-recommends "$@" ;;
    dnf)     run dnf install -y "$@" ;;
    pacman)  run pacman -S --noconfirm --needed "$@" ;;
    zypper)  run zypper --non-interactive install "$@" ;;
    apk)     run apk add --no-cache "$@" ;;
  esac
}

# -----------------------------------------------------------------------------
#  Step: install system packages
# -----------------------------------------------------------------------------
install_system_deps() {
  hdr "Step 1 / 7 — System packages"
  pkg_update
  case "$PKG_MGR" in
    apt)
      pkg_install curl ca-certificates python3 python3-venv python3-pip \
                   python3-dev build-essential git jq
      PYTHON_BIN="$(command -v python3)"
      ;;
    dnf)
      pkg_install curl ca-certificates python3 python3-pip python3-devel \
                   gcc make git jq
      PYTHON_BIN="$(command -v python3)"
      ;;
    pacman)
      pkg_install curl ca-certificates python python-pip base-devel git jq
      PYTHON_BIN="$(command -v python)"
      ;;
    zypper)
      pkg_install curl ca-certificates python3 python3-pip python3-devel \
                   git jq
      PYTHON_BIN="$(command -v python3)"
      ;;
    apk)
      pkg_install curl ca-certificates python3 py3-pip python3-dev \
                   musl-dev gcc make git jq
      PYTHON_BIN="$(command -v python3)"
      ;;
  esac
  ok "System packages installed"
}

install_python() {
  # Placeholder for systems where the default python3 is too old.
  # The package managers above will typically deliver 3.11+ on modern distros.
  err "Python ${NANOBOT_MIN_PYTHON}+ not available via ${PKG_MGR}."
  err "On Ubuntu 20.04 try:  apt install python3.11 python3.11-venv"
  err "On RHEL 8 try:         dnf install python3.11"
  exit 1
}

# -----------------------------------------------------------------------------
#  Step: create the nanobot system user
# -----------------------------------------------------------------------------
create_user() {
  hdr "Step 2 / 7 — Service user"
  if id -u "$NANOBOT_USER" >/dev/null 2>&1; then
    note "user '${NANOBOT_USER}' already exists"
  else
    run useradd --system \
                --home-dir "$NANOBOT_HOME" \
                --shell /usr/sbin/nologin \
                --comment "nanobot AI agent runtime" \
                "$NANOBOT_USER"
    ok "Created system user '${NANOBOT_USER}' (home: ${NANOBOT_HOME})"
  fi
  run mkdir -p "$NANOBOT_HOME" "$NANOBOT_CFG_DIR" "/etc/nanobot"
  run chown -R "${NANOBOT_USER}:${NANOBOT_USER}" "$NANOBOT_HOME"
  run chmod 0750 "$NANOBOT_HOME"
}

# -----------------------------------------------------------------------------
#  Step: install Ollama
# -----------------------------------------------------------------------------
install_ollama() {
  if [[ "$SKIP_OLLAMA" == "true" ]]; then
    hdr "Step 3 / 7 — Ollama  (skipped via --skip-ollama)"
    return
  fi

  hdr "Step 3 / 7 — Ollama"
  if command -v ollama >/dev/null 2>&1; then
    note "ollama already installed:  $(ollama --version 2>/dev/null || echo 'unknown version')"
  else
    log "Installing Ollama via official install script"
    # The official installer is idempotent and OS-aware
    run sh -c 'curl -fsSL https://ollama.com/install.sh | sh'
    ok "Ollama installed"
  fi

  # Write /etc/nanobot/ollama.env — the systemd unit sources it
  log "Writing ${OLLAMA_ENV_FILE}"
  run mkdir -p /etc/nanobot
  if [[ "$DRY_RUN" != "true" ]]; then
    cat > "$OLLAMA_ENV_FILE" <<EOF
# /etc/nanobot/ollama.env
# Sourced by the ollama systemd service — change here, then:
#   sudo systemctl restart ollama
OLLAMA_HOST=${OLLAMA_HOST}
OLLAMA_MODELS=${OLLAMA_MODELS_DIR}
OLLAMA_NUM_PARALLEL=${OLLAMA_NUM_PARALLEL}
OLLAMA_MAX_LOADED_MODELS=${OLLAMA_MAX_LOADED_MODELS}
OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE}
OLLAMA_FLASH_ATTENTION=${OLLAMA_FLASH_ATTENTION}
# Bigger context window — minicpm5 supports 128k; default Ollama is 2k.
# Override per-run with OLLAMA_CONTEXT_LENGTH env var or a Modelfile.
OLLAMA_CONTEXT_LENGTH_DEFAULT=${OLLAMA_CONTEXT_LENGTH}
EOF
    run chmod 0644 "$OLLAMA_ENV_FILE"
  fi

  # Make sure the models dir exists and is writable by the ollama user
  run mkdir -p "$OLLAMA_MODELS_DIR"
  if id -u ollama >/dev/null 2>&1; then
    run chown -R ollama:ollama "$OLLAMA_MODELS_DIR"
  fi

  # Patch the official ollama.service to source our env file
  if [[ -f /etc/systemd/system/ollama.service ]] && \
     ! grep -q "nanobot/ollama.env" /etc/systemd/system/ollama.service 2>/dev/null; then
    log "Patching /etc/systemd/system/ollama.service to source ${OLLAMA_ENV_FILE}"
    if [[ "$DRY_RUN" != "true" ]]; then
      # Add EnvironmentFile to [Service] if not present
      if ! grep -q "^EnvironmentFile=" /etc/systemd/system/ollama.service; then
        sed -i '/^\[Service\]/a EnvironmentFile=-/etc/nanobot/ollama.env' \
          /etc/systemd/system/ollama.service
      fi
    fi
  fi

  run systemctl daemon-reload
  run systemctl enable --now ollama.service
  ok "Ollama service is up"

  # Wait for Ollama to start accepting connections
  if [[ "$DRY_RUN" == "true" ]]; then
    note "(dry-run) would wait for Ollama to be reachable on ${OLLAMA_HOST}"
  else
    log "Waiting for Ollama API on ${OLLAMA_HOST} …"
    for i in {1..30}; do
      if curl -sf "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
        ok "Ollama is responding"
        return
      fi
      sleep 1
    done
    warn "Ollama did not respond within 30s; continuing anyway"
  fi
}

# -----------------------------------------------------------------------------
#  Step: pull the model
# -----------------------------------------------------------------------------
pull_model() {
  if [[ "$SKIP_MODEL" == "true" ]]; then
    hdr "Step 4 / 7 — Model pull  (skipped via --skip-model)"
    return
  fi

  hdr "Step 4 / 7 — Model: ${OLLAMA_MODEL}"
  # ollama list columns: NAME  ID  SIZE  MODIFIED
  if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$OLLAMA_MODEL" \
     || ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "${OLLAMA_MODEL%:*}"; then
    note "model '${OLLAMA_MODEL}' already present"
  else
    log "Pulling ${OLLAMA_MODEL}  (this can take a while on first run)"
    run ollama pull "$OLLAMA_MODEL"
    ok "Model pulled"
  fi

  # Persist context length — Ollama defaults to 2k which is too small for agents.
  # We create a tiny alias model that bakes in num_ctx.
  local alias_name="${NANOBOT_MODEL_NAME%:*}-ctx${OLLAMA_CONTEXT_LENGTH}"
  local base_name="${NANOBOT_MODEL_NAME%:*}"
  log "Setting num_ctx=${OLLAMA_CONTEXT_LENGTH} on '${base_name}' (alias: ${alias_name})"
  if [[ "$DRY_RUN" != "true" ]]; then
    cat > /tmp/Modelfile.nb <<EOF
FROM ${OLLAMA_MODEL}
PARAMETER num_ctx ${OLLAMA_CONTEXT_LENGTH}
EOF
    run ollama create "$alias_name" -f /tmp/Modelfile.nb
    rm -f /tmp/Modelfile.nb
    # Use the alias as the model nanobot will call
    NANOBOT_MODEL_NAME="$alias_name"
    ok "Model alias ready: ${NANOBOT_MODEL_NAME}"
  fi
}

# -----------------------------------------------------------------------------
#  Step: install nanobot into a venv
# -----------------------------------------------------------------------------
install_nanobot() {
  hdr "Step 5 / 7 — nanobot"
  if [[ -x "$NANOBOT_BIN" ]]; then
    note "nanobot already installed:  $("$NANOBOT_BIN" --version 2>/dev/null || echo 'unknown version')"
  else
    log "Creating venv at ${NANOBOT_VENV}"
    run mkdir -p "$(dirname "$NANOBOT_VENV")"
    run "$PYTHON_BIN" -m venv "$NANOBOT_VENV"
    run "$NANOBOT_VENV/bin/pip" install --upgrade pip wheel setuptools
    log "Installing ${NANOBOT_PKG} (this is the big one — pulls ~40 deps)"
    run "$NANOBOT_VENV/bin/pip" install "$NANOBOT_PKG"
    # Symlink for PATH convenience
    run ln -sf "$NANOBOT_BIN" /usr/local/bin/nanobot
    ok "nanobot installed → /usr/local/bin/nanobot"
  fi
}

# -----------------------------------------------------------------------------
#  Step: write the nanobot config.json
# -----------------------------------------------------------------------------
write_nanobot_config() {
  hdr "Step 6 / 7 — nanobot configuration"
  run mkdir -p "$NANOBOT_CFG_DIR" "$NANOBOT_CFG_DIR/workspace"

  # Generate a strong secret for the WebUI token. We *require* this when
  # binding to 0.0.0.0 — nanobot refuses to start otherwise.
  local secret
  secret="$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p -c 64)"

  log "Writing ${NANOBOT_CFG}"
  if [[ "$DRY_RUN" != "true" ]]; then
    cat > "$NANOBOT_CFG" <<EOF
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
      "tokenIssueSecret": "${secret}"
    }
  }
}
EOF
    run chown -R "${NANOBOT_USER}:${NANOBOT_USER}" "$NANOBOT_CFG_DIR"
    run chmod 0640 "$NANOBOT_CFG"
  fi

  # Persist the env so future re-runs / scripts can read the secret
  log "Writing ${NANOBOT_ENV_FILE}"
  if [[ "$DRY_RUN" != "true" ]]; then
    cat > "$NANOBOT_ENV_FILE" <<EOF
# /etc/nanobot/nanobot.env
NANOBOT_USER=${NANOBOT_USER}
NANOBOT_HOME=${NANOBOT_HOME}
NANOBOT_CFG=${NANOBOT_CFG}
NANOBOT_VENV=${NANOBOT_VENV}
NANOBOT_GATEWAY_HOST=${NANOBOT_GATEWAY_HOST}
NANOBOT_GATEWAY_PORT=${NANOBOT_GATEWAY_PORT}
NANOBOT_WEBUI_HOST=${NANOBOT_WEBUI_HOST}
NANOBOT_WEBUI_PORT=${NANOBOT_WEBUI_PORT}
NANOBOT_TOKEN_SECRET=${secret}
OLLAMA_HOST=${OLLAMA_HOST}
OLLAMA_MODEL=${OLLAMA_MODEL}
NANOBOT_MODEL_NAME=${NANOBOT_MODEL_NAME}
EOF
    run chmod 0640 "$NANOBOT_ENV_FILE"
  fi
  ok "nanobot config written"
}

# -----------------------------------------------------------------------------
#  Step: install + start the systemd gateway service
# -----------------------------------------------------------------------------
install_service() {
  hdr "Step 7 / 7 — systemd service"
  log "Writing ${NANOBOT_SERVICE}"
  if [[ "$DRY_RUN" != "true" ]]; then
    cat > "$NANOBOT_SERVICE" <<EOF
[Unit]
Description=nanobot gateway (HKUDS)
Documentation=https://github.com/HKUDS/nanobot
After=network-online.target ollama.service
Wants=network-online.target
Requires=ollama.service
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=${NANOBOT_USER}
Group=${NANOBOT_USER}
WorkingDirectory=${NANOBOT_HOME}
EnvironmentFile=-${NANOBOT_ENV_FILE}
Environment=HOME=${NANOBOT_HOME}
Environment=PYTHONUNBUFFERED=1
ExecStart=${NANOBOT_BIN} gateway
Restart=always
RestartSec=5
TimeoutStopSec=20

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths=${NANOBOT_HOME}
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=false

[Install]
WantedBy=multi-user.target
EOF
  fi
  run systemctl daemon-reload
  run systemctl enable --now nanobot-gateway.service
  ok "nanobot-gateway.service is enabled and started"
}

# -----------------------------------------------------------------------------
#  Optional: post-install hook (for custom MCP servers / skills / data sync)
# -----------------------------------------------------------------------------
run_post_install() {
  if [[ -x "${SCRIPT_DIR}/scripts/post-install.sh" ]]; then
    section "post-install hook (scripts/post-install.sh)"
    run "${SCRIPT_DIR}/scripts/post-install.sh"
  else
    note "no post-install.sh found — skipping custom MCP/skills hook"
  fi
}

# -----------------------------------------------------------------------------
#  Final report
# -----------------------------------------------------------------------------
print_report() {
  hdr "Install complete"
  cat <<EOF

  ${C_BOLD}nanobot:${C_RESET}        $("$NANOBOT_BIN" --version 2>/dev/null || echo 'installed')
  ${C_BOLD}ollama:${C_RESET}         $(ollama --version 2>/dev/null || echo 'installed')
  ${C_BOLD}model:${C_RESET}          ${NANOBOT_MODEL_NAME}  (from ${OLLAMA_MODEL})
  ${C_BOLD}config:${C_RESET}         ${NANOBOT_CFG}
  ${C_BOLD}workspace:${C_RESET}      ${NANOBOT_CFG_DIR}/workspace
  ${C_BOLD}logs:${C_RESET}           journalctl -u nanobot-gateway -f
                            journalctl -u ollama          -f

  ${C_BOLD}── Endpoints ──${C_RESET}
  WebUI (browser):   http://<this-vm>:${NANOBOT_WEBUI_PORT}/
  WebSocket:         ws://<this-vm>:${NANOBOT_WEBUI_PORT}/
  Gateway health:    http://<this-vm>:${NANOBOT_GATEWAY_PORT}/health
  Ollama API:        http://${OLLAMA_HOST}

  ${C_BOLD}── Auth ──${C_RESET}
  WebUI token secret is in  ${NANOBOT_ENV_FILE}  (NANOBOT_TOKEN_SECRET)
  Required because the WebUI binds to ${NANOBOT_WEBUI_HOST}.

  ${C_BOLD}── Useful commands ──${C_RESET}
  sudo ./scripts/status.sh                # health check
  sudo ./scripts/update-model.sh <name>   # swap the model
  sudo systemctl restart nanobot-gateway  # pick up config edits
  sudo -u ${NANOBOT_USER} -E ${NANOBOT_BIN} agent -m "Hello!"   # one-shot test

EOF
}

# -----------------------------------------------------------------------------
#  Main
# -----------------------------------------------------------------------------
main() {
  hdr "nanobot-vm-deploy v${SCRIPT_VERSION}"
  if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN — no changes will be made"
  fi

  # ---------------------------------------------------------------
  #  Platform dispatch: Lightning.ai Studios need different glue
  #  (no systemd, persistent /teamspace path, nohup, on_start.sh).
  #  If we detect one, delegate to the platform overlay and exit.
  # ---------------------------------------------------------------
  if [[ -d /teamspace ]]; then
    log "Detected /teamspace — looks like a Lightning AI Studio"
    log "Delegating to platform/lightning/scripts/install.sh"
    log "(use --platform=vm to force the VM path instead)"
    if [[ -f "${SCRIPT_DIR}/platform/lightning/scripts/install.sh" ]]; then
      exec bash "${SCRIPT_DIR}/platform/lightning/scripts/install.sh" "$@"
    else
      err "platform/lightning/scripts/install.sh not found"
      err "Did you forget to git clone the full repo (not just install.sh)?"
      exit 1
    fi
  fi

  require_root
  detect_os
  check_python
  install_system_deps
  create_user
  install_ollama
  pull_model
  install_nanobot
  write_nanobot_config
  install_service
  run_post_install

  if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN finished — nothing was changed"
    exit 0
  fi
  print_report
}

main "$@"
