#!/usr/bin/env bash
set -euo pipefail

APT_PACKAGES=(
  software-properties-common
)

run_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# apt-get wrapper: DEBIAN_FRONTEND doesn't survive sudo's environment reset when merely
# exported, so route it through env, which sets it directly for the exec'd process.
apt_get() { run_root env DEBIAN_FRONTEND=noninteractive apt-get -y "$@"; }

main() {
  apt_get update
  apt_get install --no-install-recommends software-properties-common

  if ! grep -Rhsq '^[[:space:]]*deb .*cappelikan/ppa' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    if ! run_root add-apt-repository -y ppa:cappelikan/ppa; then
      printf 'WARN: failed to add ppa:cappelikan/ppa; continuing without it\n' >&2
    fi
  fi

  apt_get update
  apt_get install --no-install-recommends "${APT_PACKAGES[@]}"
}

main "$@"
