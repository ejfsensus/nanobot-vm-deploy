#!/usr/bin/env bash
# scripts/lib/os-detect.sh
# Detects the Linux distro + package manager and exports PKG_MGR / OS_ID.
# Source from another script:
#     . scripts/lib/os-detect.sh

detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    err "Cannot detect OS — /etc/os-release missing"
    return 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"
  OS_VERSION="${VERSION_ID:-}"
  OS_PRETTY="${PRETTY_NAME:-${OS_ID} ${OS_VERSION}}"

  case "$OS_ID" in
    ubuntu|debian|linuxmint|pop|elementary|zorin|kali|raspbian)
      PKG_MGR="apt" ;;
    rhel|centos|rocky|almalinux|ol|nobara)
      PKG_MGR="dnf" ;;
    fedora)
      PKG_MGR="dnf" ;;
    arch|manjaro|endeavouros|garuda)
      PKG_MGR="pacman" ;;
    opensuse*|sles)
      PKG_MGR="zypper" ;;
    alpine)
      PKG_MGR="apk" ;;
    amzn)
      PKG_MGR="dnf" ;;   # Amazon Linux 2023+
    *)
      # Try ID_LIKE as a fallback
      case "$OS_LIKE" in
        *debian*|*ubuntu*) PKG_MGR="apt" ;;
        *rhel*|*fedora*|*centos*) PKG_MGR="dnf" ;;
        *arch*)            PKG_MGR="pacman" ;;
        *suse*)            PKG_MGR="zypper" ;;
        *)                 PKG_MGR="apt" ;;
      esac
      ;;
  esac
  export OS_ID OS_LIKE OS_VERSION OS_PRETTY PKG_MGR
}
