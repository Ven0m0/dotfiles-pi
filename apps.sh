#!/usr/bin/env bash
set -euo pipefail

APT_PACKAGES=(
  software-properties-common
  git
)

# Cloned so the rest of this repo's scripts (RaspberryPi/Scripts/setup.sh, dietpi.txt, etc.)
# are available locally -- this script is typically fetched and run standalone via
# `curl ... apps.sh | bash`, which only pulls this one file, not the repo.
REPO_URL='https://github.com/Ven0m0/dotfiles-pi.git'
REPO_DIR="${HOME:-/root}/dotfiles-pi"

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

clone_repo() {
  if [[ -d "$REPO_DIR/.git" ]]; then
    printf 'dotfiles-pi already present at %s, pulling latest...\n' "$REPO_DIR"
    git -C "$REPO_DIR" pull --ff-only || printf 'WARN: git pull failed; continuing with existing checkout\n' >&2
  elif ! git clone --depth 1 "$REPO_URL" "$REPO_DIR"; then
    printf 'WARN: failed to clone %s to %s; continuing without it\n' "$REPO_URL" "$REPO_DIR" >&2
  else
    printf 'Cloned dotfiles-pi to %s\n' "$REPO_DIR"
  fi
}

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

  clone_repo
}

main "$@"
