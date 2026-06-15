#!/usr/bin/env bash
# scripts/uninstall.sh
# Removes the nanobot stack installed by install.sh.
# - Stops + disables services
# - Removes systemd units
# - Removes venv + /opt/nanobot
# - Removes the nanobot system user
# - Removes /etc/nanobot/*
# - OPTIONALLY purges Ollama + its models
#
# Usage:
#   sudo ./scripts/uninstall.sh             # keep ollama + models
#   sudo ./scripts/uninstall.sh --full      # also remove ollama + models
#   sudo ./scripts/uninstall.sh --keep-user # don't remove the nanobot user/home
set -Eeuo pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=lib/logging.sh
. "${SCRIPT_DIR}/lib/logging.sh"
need_root

FULL=false
KEEP_USER=false
for arg in "$@"; do
  case "$arg" in
    --full)       FULL=true ;;
    --keep-user)  KEEP_USER=true ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--full] [--keep-user]

  --full        Also remove ollama + all model blobs
  --keep-user   Don't remove the 'nanobot' system user / home

Interactive — you will be asked to confirm before anything is removed.
EOF
      exit 0
      ;;
    *)            die "Unknown flag: $arg" ;;
  esac
done

hdr "nanobot-vm-deploy :: uninstall"
warn "This will stop nanobot-gateway and remove the nanobot install."
[[ "$FULL" == "true" ]] && warn "--full passed: ollama + all models will also be removed"
echo
read -rp "Type 'yes' to continue: " ans
[[ "$ans" == "yes" ]] || { warn "aborted"; exit 1; }

# Stop + disable services
log "Stopping services"
run systemctl disable --now nanobot-gateway.service || true

# Remove systemd unit
run rm -f /etc/systemd/system/nanobot-gateway.service
run systemctl daemon-reload

# Remove /opt/nanobot
log "Removing /opt/nanobot"
run rm -rf /opt/nanobot
run rm -f  /usr/local/bin/nanobot

# Remove /etc/nanobot (env + service config)
log "Removing /etc/nanobot"
run rm -rf /etc/nanobot

# Remove the nanobot user (if not --keep-user)
if [[ "$KEEP_USER" != "true" ]]; then
  if id -u nanobot >/dev/null 2>&1; then
    log "Removing user 'nanobot' and home"
    run userdel -r nanobot 2>/dev/null || run userdel nanobot
  fi
fi

# Optional: full purge of Ollama
if [[ "$FULL" == "true" ]]; then
  warn "Purging Ollama"
  run systemctl disable --now ollama.service || true
  if command -v ollama >/dev/null 2>&1; then
    run sh -c 'curl -fsSL https://ollama.com/install.sh | sh -s -- --uninstall' || true
  fi
  run rm -f /etc/systemd/system/ollama.service /etc/systemd/system/default.target.wants/ollama.service
  run rm -rf /usr/local/bin/ollama /usr/share/ollama /var/lib/ollama
  if id -u ollama >/dev/null 2>&1; then
    run userdel -r ollama 2>/dev/null || run userdel ollama
  fi
  run systemctl daemon-reload
fi

ok "uninstall complete"
echo
echo "  Re-install:  sudo ./install.sh"
echo "  Full reset:  sudo ./scripts/uninstall.sh --full && sudo ./install.sh"
