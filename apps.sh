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

main() {
  export DEBIAN_FRONTEND=noninteractive

  run_root apt-get update
  run_root apt-get install -y --no-install-recommends software-properties-common

  if ! grep -Rhsq '^[[:space:]]*deb .*cappelikan/ppa' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    if ! run_root add-apt-repository -y ppa:cappelikan/ppa; then
      printf 'WARN: failed to add ppa:cappelikan/ppa; continuing without it\n' >&2
    fi
  fi

  run_root apt-get update
  run_root apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
}

main "$@"
