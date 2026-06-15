#!/usr/bin/env bash
# scripts/lib/logging.sh
# Sourced by all other scripts — provides log/ok/warn/err/hdr helpers
# and a run() that honours DRY_RUN.

# Auto-detect colour support
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
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

# Default DRY_RUN off — override with DRY_RUN=true ./script.sh
: "${DRY_RUN:=false}"

log()    { printf "%s[•]%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
ok()     { printf "%s[✓]%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
warn()   { printf "%s[!]%s %s\n" "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()    { printf "%s[✗]%s %s\n" "$C_RED"    "$C_RESET" "$*" >&2; }
hdr()    { printf "\n%s%s== %s ==%s\n" "$C_BOLD" "$C_CYAN" "$*" "$C_RESET"; }
section(){ printf "\n%s%s── %s ──%s\n" "$C_BOLD" "$C_DIM" "$*" "$C_RESET"; }
note()   { printf "  %s↳%s %s\n" "$C_DIM" "$C_RESET" "$*"; }

# run <cmd...>
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "  %s(dry-run)%s %s\n" "$C_DIM" "$C_RESET" "$*"
  else
    "$@"
  fi
}

# die <msg> — print error and exit 1
die() { err "$*"; exit 1; }

# need_root
need_root() {
  [[ $EUID -eq 0 ]] || die "must run as root (or with sudo)"
}
