#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t' LC_ALL=C DEBIAN_FRONTEND=noninteractive
# DESCRIPTION: System fixes for Raspberry Pi - time sync, SSH permissions, Nextcloud
#              Targets: Debian/Raspbian, DietPi
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" && SCRIPT_DIR="$(pwd -P)" || exit 1
# Colors
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m'
DEF=$'\e[0m' BLD=$'\e[1m'
# Core helpers
has() { command -v -- "$1" &>/dev/null; }
pkg_installed() { [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null) == installed ]]; }
log() { printf '%b\n' "${GRN}▶${DEF} $*"; }
warn() { printf '%b\n' "${YLW}⚠${DEF} $*" >&2; }
err() { printf '%b\n' "${RED}✗${DEF} $*" >&2; }
die() {
  err "$1"
  exit "${2:-1}"
}

usage() {
  cat <<'EOF'
Fix.sh - System fixes for Raspberry Pi
Usage: Fix.sh [OPTIONS]
Options:
  -h, --help    Show this help
Performs:
  • Time sync (ntpdate)
  • CA certificates installation
  • SSH permissions fix
  • GnuPG permissions fix
  • Nextcloud container permissions (if exists)
EOF
}

# Parse arguments
parse_args() {
  while (($#)); do
    case "$1" in
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        die "invalid option: $1"
        ;;
      *) break ;;
    esac
    shift
  done
}

# Time synchronization
fix_time_sync() {
  log "Fixing time synchronization"
  if ! pkg_installed ntpdate; then
    sudo apt-get update -qq
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y ntpdate || warn "Failed to install ntpdate"
  fi
  if has ntpdate; then
    sudo ntpdate -u ntp.ubuntu.com || warn "Failed to sync time with ntp.ubuntu.com"
  fi
}

# CA certificates
fix_ca_certificates() {
  log "Ensuring CA certificates are installed"
  if ! pkg_installed ca-certificates; then
    sudo apt-get update -qq
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates || warn "Failed to install ca-certificates"
  else
    log "CA certificates already installed"
  fi
}

# SSH permissions
fix_ssh_permissions() {
  log "Fixing SSH permissions"
  if [[ -d ~/.ssh ]]; then
    # Use standard find for reliability
    find ~/.ssh -type f -exec chmod 600 {} +
    find ~/.ssh -type d -exec chmod 700 {} +
    find ~/.ssh -type f -name "*.pub" -exec chmod 644 {} +
    chmod 700 ~/.ssh
    log "SSH permissions fixed"
  else
    warn "$HOME/.ssh directory not found, skipping"
  fi
}

# GnuPG permissions
fix_gnupg_permissions() {
  log "Fixing GnuPG permissions"
  if [[ -d ~/.gnupg ]]; then
    chmod 700 ~/.gnupg
    log "GnuPG permissions fixed"
  else
    warn "$HOME/.gnupg directory not found, skipping"
  fi
}

# Nextcloud container fix
fix_nextcloud() {
  log "Checking for Nextcloud container"
  if ! has docker; then
    warn "Docker not found, skipping Nextcloud fix"
    return 0
  fi

  if ! sudo docker ps --format '{{.Names}}' | grep -q '^nextcloud$'; then
    warn "Nextcloud container not running, skipping"
    return 0
  fi

  log "Fixing Nextcloud /tmp permissions"
  if ! sudo docker exec nextcloud sh -c '
    set -eu
    if [ -e /tmp ] && [ ! -d /tmp ]; then
      rm -f /tmp
    fi
    mkdir -p /tmp
    if getent group www-data >/dev/null 2>&1; then
      chown root:www-data /tmp
      chmod 2770 /tmp
    else
      chown root:root /tmp
      chmod 1777 /tmp
    fi
  '; then
    warn "Failed to fix /tmp permissions in nextcloud"
  else
    log "Nextcloud permissions fixed"
  fi
}

# Main execution
main() {
  parse_args "$@"
  log "${BLD}Raspberry Pi System Fixes${DEF}"

  fix_time_sync
  fix_ca_certificates
  fix_ssh_permissions
  fix_gnupg_permissions
  fix_nextcloud

  log "${GRN}✓${DEF} All fixes complete"
}

main "$@"
