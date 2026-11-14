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
# Pinned release: review a new tag before bumping. Cloned instead of `curl | bash` so the code that
# runs as root is a tagged, inspectable git checkout.
PIHOLE_TAG=v6.6
PIHOLE_SRC=/tmp/pi-hole-src

# Pi-hole's installer shows an interface-selection dialog whenever more than one network
# interface is present; with exactly one available it auto-selects without prompting. Force
# wired-only so that holds on a Pi with both eth0 and wlan0. Remove this line (and install
# manually afterward instead) if this device is meant to run Pi-hole over WiFi.
ip link set wlan0 down 2>/dev/null || :

{
  echo "=== Pi-hole unattended install: $(date -Is) ==="
  rm -rf "$PIHOLE_SRC"
  if git clone --quiet --depth 1 --branch "$PIHOLE_TAG" https://github.com/pi-hole/pi-hole "$PIHOLE_SRC" &&
    bash "$PIHOLE_SRC/automated install/basic-install.sh" --unattended; then
    echo
    echo "Pi-hole installed. Admin password: see 'pihole setpassword' output above,"
    echo "or set a new one any time with: pihole -a -p"
  else
    echo
    echo "Pi-hole unattended install FAILED (see output above)."
    echo "Install manually instead: RaspberryPi/Scripts/setup.sh -p"
  fi
} >>"$LOG" 2>&1
