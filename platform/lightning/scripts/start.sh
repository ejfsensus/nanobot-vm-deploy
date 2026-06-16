#!/usr/bin/env bash
# =============================================================================
#  scripts/start.sh
#  -------------------------------------------------------------------
#  Manually bring the stack up from inside a Lightning Studio terminal.
#  Same effect as the on-start hook, but intended for interactive use
#  (e.g. after editing config or upgrading the model).
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
INSTALL_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

# Delegate to the on-start script (idempotent)
exec "${INSTALL_ROOT}/.lightning_studio/on_start.sh"
