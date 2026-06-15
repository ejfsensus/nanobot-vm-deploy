#!/usr/bin/env bash
# scripts/lib/system.sh
# Cross-distro package + service helpers. Source from another script:
#     . scripts/lib/logging.sh
#     . scripts/lib/os-detect.sh
#     . scripts/lib/system.sh
# Requires PKG_MGR to be exported (call detect_os first).

pkg_update() {
  case "$PKG_MGR" in
    apt)     run apt-get update -y ;;
    dnf)     run dnf -y makecache ;;
    pacman)  run pacman -Sy --noconfirm ;;
    zypper)  run zypper --non-interactive refresh ;;
    apk)     run apk update ;;
    *)       err "pkg_update: unknown PKG_MGR: $PKG_MGR"; return 1 ;;
  esac
}

pkg_install() {
  case "$PKG_MGR" in
    apt)     run apt-get install -y --no-install-recommends "$@" ;;
    dnf)     run dnf install -y "$@" ;;
    pacman)  run pacman -S --noconfirm --needed "$@" ;;
    zypper)  run zypper --non-interactive install "$@" ;;
    apk)     run apk add --no-cache "$@" ;;
    *)       err "pkg_install: unknown PKG_MGR: $PKG_MGR"; return 1 ;;
  esac
}

# service_active <name>  — returns 0 if active, 1 otherwise
service_active() {
  systemctl is-active --quiet "$1"
}

# service_enable_now <name>  — enable + start, honours DRY_RUN
service_enable_now() {
  run systemctl enable --now "$1"
}

# wait_for_http <url> [timeout_seconds]  — polls until 2xx/3xx
wait_for_http() {
  local url="$1" timeout="${2:-30}" i
  for ((i=0; i<timeout; i++)); do
    if curl -sf -o /dev/null --max-time 2 "$url"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# read_env <file> <key>  — grep a KEY=VALUE from an env file (simple parser)
read_env() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  grep -E "^${key}=" "$file" | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}
