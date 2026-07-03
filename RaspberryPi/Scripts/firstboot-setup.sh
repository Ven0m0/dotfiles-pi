#!/usr/bin/env bash
# shellcheck shell=bash
# DESCRIPTION: Chains RaspberryPi/Scripts/setup.sh with the right flags for this specific
#              device. Meant to be the actual dietpi.txt AUTO_SETUP_CUSTOM_SCRIPT_EXEC target
#              -- DietPi downloads and runs one script with no arguments, so this fetches
#              setup.sh itself and picks its flags based on the detected Raspberry Pi model:
#                - Pi-hole (-p): always
#                - Nextcloud (-n): Raspberry Pi 4 only -- Nextcloud's MariaDB+PHP+webserver
#                  stack is too heavy to default on for a Pi 3's 1GB RAM
set -uo pipefail

SETUP_URL='https://raw.githubusercontent.com/Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/Scripts/setup.sh'
LOG=/var/log/dietpi-firstboot-setup.log

model=$(tr -d '\0' </proc/device-tree/model 2>/dev/null || :)

flags=(-p)
[[ $model == *'Raspberry Pi 4'* ]] && flags+=(-n)

{
  echo "=== firstboot-setup.sh: $(date -Is) ==="
  echo "Detected model: ${model:-unknown}"
  echo "setup.sh flags: ${flags[*]}"

  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  if curl -fsSL --proto '=https' --tlsv1.3 --max-time 300 -o "$tmp" "$SETUP_URL"; then
    bash "$tmp" "${flags[@]}"
  else
    echo "Failed to download setup.sh from $SETUP_URL"
  fi
} >>"$LOG" 2>&1
