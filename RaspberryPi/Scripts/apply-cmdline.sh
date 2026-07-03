#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail
# DESCRIPTION: Apply this repo's tuned kernel cmdline parameters to an existing
#              Raspberry Pi / DietPi cmdline.txt, without touching that file's
#              own "root=" entry (device-specific: tied to one SD card's
#              partition table, and never safe to copy between cards).

# Parameter set captured from this repo's cmdline.txt. May contain repeated keys
# (e.g. "console=") -- order among entries for the same key matters (first
# console= becomes the primary /dev/console), order between different keys does not.
# The comma in console=serial0,115200 below is a real part of that kernel parameter's
# syntax, not a mistaken array-element separator.
# shellcheck disable=SC2054
MANAGED_PARAMS=(
  rootfstype=ext4
  rootwait
  fsck.repair=yes
  net.ifnames=0
  logo.nologo
  console=serial0,115200
  console=tty1
  mitigations=off
  nowatchdog
  transparent_hugepage=madvise
  init_on_alloc=0
  init_on_free=0
  page_alloc.shuffle=0
  workqueue.power_efficient=0
  threadirqs
  skew_tick=1
  loglevel=3
  quiet
  systemd.unified_cgroup_hierarchy=1
)

usage() {
  cat <<'EOF'
apply-cmdline.sh - apply this repo's tuned kernel cmdline parameters to a cmdline.txt

Usage: apply-cmdline.sh <path-to-cmdline.txt>

For each managed parameter above:
  - If the target already sets that key, its value is replaced.
  - If the target doesn't have it, it's appended.
Anything else already in the target -- most importantly "root=..." -- is left
untouched. A timestamped backup of the target is written alongside it first.
EOF
}

[[ $# -eq 1 ]] || { usage; exit 1; }
target=$1
[[ -f $target ]] || { echo "error: $target: no such file" >&2; exit 1; }
[[ $(wc -l <"$target") -le 1 ]] || {
  echo "error: $target has more than one line; refusing to touch a file that isn't a plain cmdline.txt" >&2
  exit 1
}

current=$(<"$target")
if [[ $current != *root=* ]]; then
  echo "warning: $target has no root= entry -- this script never sets one, so the result will not be bootable until root= is added" >&2
fi

backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
cp -- "$target" "$backup"
echo "Backed up $target -> $backup"

# Distinct keys this script manages, used to strip any existing occurrences (including
# duplicates like repeated "console=" entries) before re-appending the managed set fresh.
declare -A managed_keys
for p in "${MANAGED_PARAMS[@]}"; do
  managed_keys[${p%%=*}]=1
done

new_params=()
for tok in $current; do
  key=${tok%%=*}
  [[ -n ${managed_keys[$key]:-} ]] || new_params+=("$tok")
done
new_params+=("${MANAGED_PARAMS[@]}")

printf '%s\n' "${new_params[*]}" >"$target"
echo "Updated $target"
