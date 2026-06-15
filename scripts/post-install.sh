#!/usr/bin/env bash
# scripts/post-install.sh
# =============================================================================
#  YOUR AMENDMENT HOOK
#  -------------------------------------------------------------------
#  Runs at the END of every `./install.sh` invocation (initial install,
#  re-run, model swap, etc.). This is the place to:
#
#    * install / register custom MCP servers
#    * drop in custom skills (the nanobot skill format)
#    * seed the workspace with prompt files, knowledge bases, etc.
#    * run any first-boot data sync
#
#  Everything is executed as root, AFTER the nanobot user, venv, and
#  config are in place. Use `run_as_nanobot` to drop privileges.
#
#  Edit freely. The `mcp/` and `skills/` directories in the repo are
#  yours to populate — they're mounted/copied to the right places below.
# =============================================================================
set -Eeuo pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# shellcheck source=lib/logging.sh
. "${SCRIPT_DIR}/lib/logging.sh"

# Pull current env (NANOBOT_HOME, NANOBOT_USER, NANOBOT_CFG_DIR, etc.)
ENV_FILE="/etc/nanobot/nanobot.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
else
  warn "post-install: ${ENV_FILE} missing — install.sh may not have finished"
  exit 0
fi

REPO_DIR="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

run_as_nanobot() {
  if id -u "$NANOBOT_USER" >/dev/null 2>&1; then
    run sudo -u "$NANOBOT_USER" -H -E "$@"
  else
    warn "user ${NANOBOT_USER} not present — skipping run_as_nanobot: $*"
  fi
}

hdr "post-install :: custom MCP servers"
# ---------------------------------------------------------------------------
#  1. CUSTOM MCP SERVERS
#  ---------------------------------------------------------------------------
#  Drop a folder per server under mcp/servers/<server-name>/. Each folder
#  should at minimum contain:
#      mcp/servers/<server-name>/install.sh   (optional, runs once)
#      mcp/servers/<server-name>/config.json  (gets copied to ~/.nanobot/)
#  Uncomment the block below to enable the wiring. The block is shipped
#  commented-out so a fresh install with empty mcp/ doesn't fail.
#
#  if [[ -d "${REPO_DIR}/mcp/servers" ]]; then
#    for srv in "${REPO_DIR}/mcp/servers"/*/; do
#      [[ -d "$srv" ]] || continue
#      name="$(basename "$srv")"
#      log "MCP server: ${name}"
#      if [[ -x "${srv}install.sh" ]]; then
#        run bash "${srv}install.sh"
#      fi
#      if [[ -f "${srv}config.json" ]]; then
#        run cp "${srv}config.json" "${NANOBOT_CFG_DIR}/${name}.mcp.json"
#        run chown "${NANOBOT_USER}:${NANOBOT_USER}" "${NANOBOT_CFG_DIR}/${name}.mcp.json"
#      fi
#    done
#  else
#    note "no mcp/servers/ — nothing to wire"
#  fi

note "no MCP servers wired (edit scripts/post-install.sh to enable)"

# ---------------------------------------------------------------------------
#  2. CUSTOM SKILLS
#  ---------------------------------------------------------------------------
#  nanobot discovers skills under  ~/.nanobot/workspace/skills/<name>/SKILL.md
#  Copy any skill folders in skills/ to that location.
hdr "post-install :: custom skills"
if [[ -d "${REPO_DIR}/skills" ]]; then
  shopt -s nullglob
  for skill in "${REPO_DIR}/skills"/*/; do
    [[ -d "$skill" ]] || continue
    [[ -f "${skill}SKILL.md" ]] || { note "skipping $(basename "$skill") (no SKILL.md)"; continue; }
    name="$(basename "$skill")"
    target="${NANOBOT_CFG_DIR}/workspace/skills/${name}"
    log "Installing skill: ${name}  →  ${target}"
    run mkdir -p "${NANOBOT_CFG_DIR}/workspace/skills"
    run cp -r "$skill" "${NANOBOT_CFG_DIR}/workspace/skills/"
    run chown -R "${NANOBOT_USER}:${NANOBOT_USER}" "${NANOBOT_CFG_DIR}/workspace/skills"
  done
  shopt -u nullglob
else
  note "no skills/ directory — nothing to install"
fi

# ---------------------------------------------------------------------------
#  3. WORKSPACE SEED (optional)
#  ---------------------------------------------------------------------------
hdr "post-install :: workspace seed"
# Drop any AGENTS.md, prompts, or starter files into the workspace here.
# Example:
#   if [[ -f "${REPO_DIR}/workspace/AGENTS.md" ]]; then
#     run cp "${REPO_DIR}/workspace/AGENTS.md" "${NANOBOT_CFG_DIR}/workspace/"
#     run chown "${NANOBOT_USER}:${NANOBOT_USER}" "${NANOBOT_CFG_DIR}/workspace/AGENTS.md"
#   fi
note "no seed files specified"

# ---------------------------------------------------------------------------
#  4. ONE-SHOT DATA SYNC (optional)
#  ---------------------------------------------------------------------------
#  Add any pull-from-S3, fetch-from-API, etc. logic here. Runs as root.
#  If you need to run as the nanobot user, use:
#      run_as_nanobot <command>

ok "post-install hook finished"
