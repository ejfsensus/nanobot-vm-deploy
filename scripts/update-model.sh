#!/usr/bin/env bash
# scripts/update-model.sh
# Swap the Ollama model the gateway uses, without re-running the full install.
#
# Usage:
#   sudo ./scripts/update-model.sh                          # re-deploy current OLLAMA_MODEL
#   sudo ./scripts/update-model.sh qwen2.5:7b               # pull + wire a new model
#   sudo ./scripts/update-model.sh llama3.1:8b 16384        # custom context length
#   sudo ./scripts/update-model.sh --list                   # show what's available locally
set -Eeuo pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=lib/logging.sh
. "${SCRIPT_DIR}/lib/logging.sh"
need_root

ENV_FILE="/etc/nanobot/nanobot.env"
OLLAMA_ENV_FILE="/etc/nanobot/ollama.env"

usage() {
  cat <<EOF
Usage: $0 [MODEL] [CONTEXT_LENGTH]

  MODEL            Ollama model name (e.g. qwen2.5:7b, llama3.1:8b)
                   Defaults to the value of OLLAMA_MODEL in /etc/nanobot/nanobot.env
  CONTEXT_LENGTH   num_ctx to bake into the alias. Defaults to OLLAMA_CONTEXT_LENGTH_DEFAULT
                   from /etc/nanobot/ollama.env

Flags:
  --list           List local Ollama models and exit
  --remove ALIAS   Delete the named alias/model and exit
  --help           Show this help

Examples:
  $0
  $0 qwen2.5:7b
  $0 llama3.1:8b 32768
  $0 --list
EOF
}

# --- arg parsing (pre-env, so --help works without an install)
ACTION="swap"
MODEL_ARG=""
CTX_ARG=""
if [[ $# -eq 0 ]]; then
  : # defaults below
elif [[ "$1" == "--help" || "$1" == "-h" ]]; then
  usage; exit 0
elif [[ "$1" == "--list" ]]; then
  if ! command -v ollama >/dev/null 2>&1; then
    die "ollama is not installed (or not on PATH)"
  fi
  hdr "Local Ollama models"
  ollama list
  exit 0
elif [[ "$1" == "--remove" ]]; then
  [[ -n "${2:-}" ]] || die "--remove requires an alias name"
  ACTION="remove"
  REMOVE_TARGET="$2"
else
  MODEL_ARG="${1}"
  CTX_ARG="${2:-}"
fi

# --- from here on we need a real install
[[ -f "$ENV_FILE" ]] || die "env file not found at ${ENV_FILE} — has install.sh been run?"
# shellcheck disable=SC1090
. "$ENV_FILE"
[[ -f "$OLLAMA_ENV_FILE" ]] && . "$OLLAMA_ENV_FILE" || true

case "$ACTION" in
  remove)
    warn "Removing model: ${REMOVE_TARGET}"
    ollama rm "$REMOVE_TARGET" || die "ollama rm failed"
    ok "removed"
    exit 0
    ;;
  swap)
    TARGET_MODEL="${MODEL_ARG:-${OLLAMA_MODEL}}"
    TARGET_CTX="${CTX_ARG:-$(grep -E '^OLLAMA_CONTEXT_LENGTH_DEFAULT=' /etc/nanobot/ollama.env 2>/dev/null | cut -d= -f2)}"
    TARGET_CTX="${TARGET_CTX:-8192}"
    LEAF_NAME="${TARGET_MODEL##*/}"     # strip namespace: openbmb/minicpm5:latest → minicpm5:latest
    ALIAS_NAME="${LEAF_NAME%:*}-ctx${TARGET_CTX}"

    hdr "Updating model → ${TARGET_MODEL}  (alias: ${ALIAS_NAME}, num_ctx=${TARGET_CTX})"

    # 1. Make sure the base model is present
    #    ollama list output columns: NAME  ID  SIZE  MODIFIED
    if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$TARGET_MODEL" \
       || ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "${TARGET_MODEL%:*}"; then
      note "base model '${TARGET_MODEL}' already present"
    else
      log "Pulling ${TARGET_MODEL}  (this can take a while)"
      ollama pull "$TARGET_MODEL" || die "ollama pull failed"
    fi

    # 2. (Re)create the num_ctx alias
    log "Creating alias ${ALIAS_NAME} with num_ctx=${TARGET_CTX}"
    cat > /tmp/Modelfile.nb <<EOF
FROM ${TARGET_MODEL}
PARAMETER num_ctx ${TARGET_CTX}
EOF
    ollama rm  "$ALIAS_NAME" >/dev/null 2>&1 || true
    ollama create "$ALIAS_NAME" -f /tmp/Modelfile.nb || die "ollama create failed"
    rm -f /tmp/Modelfile.nb

    # 3. Patch nanobot config to point at the new alias
    log "Patching ${NANOBOT_CFG}"
    # backup
    cp -a "$NANOBOT_CFG" "${NANOBOT_CFG}.bak.$(date +%s)" 2>/dev/null || true
    jq --arg m "$ALIAS_NAME" \
       '.providers.local.model = $m
        | (.modelPresets["default"].model) = $m' \
       "$NANOBOT_CFG" > "${NANOBOT_CFG}.tmp" \
      && mv "${NANOBOT_CFG}.tmp" "$NANOBOT_CFG"
    chown "${NANOBOT_USER}:${NANOBOT_USER}" "$NANOBOT_CFG"
    chmod 0640 "$NANOBOT_CFG"

    # 4. Persist new env values
    sed -i \
      -e "s|^OLLAMA_MODEL=.*|OLLAMA_MODEL=${TARGET_MODEL}|" \
      -e "s|^NANOBOT_MODEL_NAME=.*|NANOBOT_MODEL_NAME=${ALIAS_NAME}|" \
      "$ENV_FILE"

    # 5. Bounce the gateway so it picks up the new config
    log "Restarting nanobot-gateway"
    systemctl restart nanobot-gateway

    ok "model swapped"
    echo
    echo "  Ollama:  ${TARGET_MODEL}"
    echo "  Alias:   ${ALIAS_NAME}  (num_ctx=${TARGET_CTX})"
    echo "  Config:  ${NANOBOT_CFG}"
    echo "  Status:  sudo ./scripts/status.sh"
    ;;
esac
