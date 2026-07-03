#!/usr/bin/env bash
# shellcheck shell=bash
# DESCRIPTION: Unattended Pi-hole install, meant to run as DietPi's post-install custom
#              script (dietpi.txt's AUTO_SETUP_CUSTOM_SCRIPT_EXEC), i.e. after first-boot
#              provisioning and networking are already up.
#
# Deliberately does not `set -e`: Pi-hole's own installer can still show a whiptail/dialog
# prompt in edge cases (e.g. DNS provider selection) despite --unattended. Since there is no
# controlling TTY on a first-boot custom script, any such prompt fails fast rather than
# hanging (verified: whiptail exits immediately, non-zero, with no TTY) -- this script catches
# that failure, logs it, and exits cleanly so it never blocks the rest of DietPi's first-boot
# chain. Worst case: Pi-hole isn't installed yet and the log says so; install manually
# afterward with RaspberryPi/Scripts/setup.sh -p.
set -uo pipefail

LOG=/var/log/pihole-unattended-install.log

# Pi-hole's installer shows an interface-selection dialog whenever more than one network
# interface is present; with exactly one available it auto-selects without prompting. Force
# wired-only so that holds on a Pi with both eth0 and wlan0. Remove this line (and install
# manually afterward instead) if this device is meant to run Pi-hole over WiFi.
ip link set wlan0 down 2>/dev/null || :

{
  echo "=== Pi-hole unattended install: $(date -Is) ==="
  if curl -fsSL https://install.pi-hole.net | bash -s -- --unattended; then
    echo
    echo "Pi-hole installed. Admin password: see 'pihole setpassword' output above,"
    echo "or set a new one any time with: pihole -a -p"
  else
    echo
    echo "Pi-hole unattended install FAILED (see output above)."
    echo "Install manually instead: RaspberryPi/Scripts/setup.sh -p"
  fi
} >>"$LOG" 2>&1
