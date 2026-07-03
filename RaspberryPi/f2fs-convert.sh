#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
# F2FS conversion: clone a DietPi/Raspbian ext4 image (or device) to an F2FS root,
# preserving the source partition table and only reformatting the root partition.
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C

R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' B=$'\e[34m' X=$'\e[0m'
has() { command -v -- "$1" &>/dev/null; }
msg() { printf '%s\n' "$@"; }
log() { printf '%b[INF]%b %s\n' "$B" "$X" "$*" >&2; }
warn() { printf '%b[WRN]%b %s\n' "$Y" "$X" "$*" >&2; }
die() {
  printf '%b[ERR]%b %s\n' "$R" "$X" "$1" >&2
  exit "${2:-1}"
}
need() { has "$1" || die "Missing dependency: $1"; }

MOUNTS=()
cleanup() {
  set +e
  local d
  for d in "${MOUNTS[@]}"; do
    umount -R "$d" &>/dev/null || umount -lf "$d" &>/dev/null
  done
  [[ -n ${LOOP_SRC:-} ]] && losetup -d "$LOOP_SRC" &>/dev/null
  [[ -n ${LOOP_DST:-} ]] && losetup -d "$LOOP_DST" &>/dev/null
  [[ -n ${LOCK_FD:-} ]] && exec {LOCK_FD}>&- 2>/dev/null
  [[ -n ${LOCK:-} && -f ${LOCK:-} ]] && rm -f "$LOCK"
  [[ -n ${WORKDIR:-} && -d ${WORKDIR:-} ]] && rm -rf -- "$WORKDIR"
}
trap cleanup EXIT INT TERM

DIETPI_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Trixie.img.xz"

usage() {
  cat <<EOF
Usage:
  f2fs-convert.sh [OPTIONS]

Options:
  --src URL|FILE|dietpi  Source image (https URL, local file, or "dietpi" for the latest image)
  --out FILE             Output image path
  --device DEV            Flash to device instead of creating an image
  --root-label LABEL      Root partition label (default: dietpi-root)
  --root-opts "opts"      F2FS mount options (also written to rootflags=/fstab)
  --shrink                 Shrink the source ext4 filesystem before cloning
  --ssh                    Enable SSH on first boot (touch /boot/ssh)
  --dry-run                 Validate inputs and print the plan; make no changes
  --no-usb-check            Skip the USB/MMC transport check on --device targets
  --no-size-check           Skip the source-fits-on-device size check
  -i, --interactive        Interactive mode with fzf selection
  -h, --help                Show this help

Defaults:
  Source: $DIETPI_URL
  Output: ./DietPi_RPi234-ARMv8-Trixie_f2fs.img
  Label:  dietpi-root
  Opts:   compress_algorithm=zstd,compress_chksum,atgc,gc_merge,background_gc=on,lazytime

Examples:
  # Download and convert DietPi (interactive)
  sudo ./f2fs-convert.sh -i

  # Use a local image file
  sudo ./f2fs-convert.sh --src ~/DietPi.img.xz --out ~/dietpi-f2fs.img

  # Shrink then flash directly to a device
  sudo ./f2fs-convert.sh --src dietpi --device /dev/mmcblk0 --shrink --ssh
EOF
}

select_source() {
  has fzf || die "fzf required for interactive mode. Install: sudo apt install fzf"

  msg "Select source image:\n"
  local -a choices=(
    "1|Download DietPi Trixie (latest)"
    "2|Local image file"
    "3|Custom URL"
  )

  local choice
  choice=$(printf '%s\n' "${choices[@]}" | fzf --height 10 --prompt="Source> " --with-nth=2 -d'|' | cut -d'|' -f1)

  case "$choice" in
    1) SRC_URL="$DIETPI_URL" ;;
    2)
      SRC_URL=$(find . -maxdepth 3 \( -name "*.img" -o -name "*.img.xz" \) 2>/dev/null \
        | fzf --prompt="Select image> " --preview='ls -lh {}')
      [[ -n $SRC_URL ]] || die "No image selected"
      ;;
    3)
      printf 'Enter URL: '
      read -r SRC_URL
      [[ -n $SRC_URL ]] || die "No URL provided"
      ;;
    *) die "No source selected" ;;
  esac

  log "Source: $SRC_URL"
}

select_output() {
  has fzf || die "fzf required for interactive mode"

  msg "Select output:\n"
  local -a choices=(
    "1|Create image file"
    "2|Flash to device"
  )

  local choice
  choice=$(printf '%s\n' "${choices[@]}" | fzf --height 10 --prompt="Output> " --with-nth=2 -d'|' | cut -d'|' -f1)

  case "$choice" in
    1)
      printf 'Output image path [%s]: ' "$OUT_IMG"
      local user_out
      read -r user_out
      [[ -n $user_out ]] && OUT_IMG="$user_out"
      OUTPUT_DEVICE=""
      ;;
    2)
      OUTPUT_DEVICE=$(lsblk -pndo NAME,MODEL,SIZE,TRAN,TYPE \
        | awk -v s="$NO_USB_CHECK" 'tolower($0)~/disk/&&(s=="1"||tolower($0)~/usb|mmc/)' \
        | fzf --prompt="Select device (DATA WILL BE ERASED)> " --preview='lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT {1}' \
        | awk '{print $1}')
      [[ -n $OUTPUT_DEVICE ]] || die "No device selected"
      OUT_IMG=""
      log "Device: $OUTPUT_DEVICE"
      ;;
    *) die "No output selected" ;;
  esac
}

domount() {
  local src=$1 dst=$2
  shift 2
  mkdir -p "$dst"
  mount "$@" "$src" "$dst"
  MOUNTS+=("$dst")
}

read_part_geom() {
  local disk="$1" partnum="$2"
  parted -m -s "$disk" unit s print | awk -F: -v p="$partnum" '$1==p {gsub(/s/,"",$2); gsub(/s/,"",$3); print $2, $3}'
}

shrink_src_image() {
  log "Shrinking source image before conversion..."
  local p_out start num loop
  p_out="$(parted -ms "$SRC_IMG" unit B print)"
  start="$(awk -F: 'END{print $2}' <<<"$p_out" | tr -d B)"
  num="$(awk -F: 'END{print $1}' <<<"$p_out")"
  loop="$(losetup -f --show -o "$start" "$SRC_IMG")" || die "Loop setup failed for shrink"
  e2fsck -pf "$loop" || e2fsck -fy "$loop" || die "Filesystem check failed during shrink"

  local tune_out sz_blk sz_cur sz_min
  tune_out="$(tune2fs -l "$loop")"
  read -r _ _ _ sz_blk < <(grep "Block size" <<<"$tune_out")
  read -r _ _ _ sz_cur < <(grep "Block count" <<<"$tune_out")
  sz_min="$(resize2fs -P "$loop" 2>/dev/null | awk -F: '{print $2}')"
  sz_min=$((sz_min + 5000)) # safety buffer

  if ((sz_cur > sz_min)); then
    resize2fs -p "$loop" "$sz_min" || die "Resize failed during shrink"
    local end_b=$((start + sz_min * sz_blk))
    losetup -d "$loop"
    parted -s "$SRC_IMG" rm "$num" mkpart primary "$start"B "$end_b"B
    truncate -s "$end_b" "$SRC_IMG"
    log "Shrunk source image to $((end_b / 1024 / 1024))MB"
  else
    log "Source image already minimal"
    losetup -d "$loop"
  fi
}

remove_ext4_configs() {
  local root_mnt="$1"

  log "Removing ext4-specific configs..."

  local mke2fs_conf="$root_mnt/etc/mke2fs.conf"
  if [[ -f $mke2fs_conf ]] && grep -q "journal" "$mke2fs_conf" 2>/dev/null; then
    log "Removed ext4 journal settings from mke2fs.conf"
    sed -i '/journal/d' "$mke2fs_conf"
  fi

  local cron_dir="$root_mnt/etc/cron.d"
  if [[ -d $cron_dir ]]; then
    local f
    for f in "$cron_dir"/*; do
      [[ -f $f ]] || continue
      if grep -qi "e2fsck\|tune2fs\|ext4" "$f" 2>/dev/null; then
        log "Removed ext4-specific cron job: ${f##*/}"
        rm -f "$f"
      fi
    done
  fi

  local systemd_dir="$root_mnt/etc/systemd/system"
  if [[ -d $systemd_dir ]]; then
    local f
    for f in "$systemd_dir"/*.timer; do
      [[ -f $f ]] || continue
      if grep -qi "e2fsck\|tune2fs\|ext4" "$f" 2>/dev/null; then
        log "Removed ext4-specific systemd timer: ${f##*/}"
        rm -f "$f"
        rm -f "${f%.timer}.service" 2>/dev/null || :
      fi
    done
  fi

  log "ext4-specific configs removed"
}

add_f2fs_to_initramfs() {
  local root_mnt="$1"
  local initramfs_modules="$root_mnt/etc/initramfs-tools/modules"
  local boot_dir="$root_mnt/boot"

  if [[ ! -d "$root_mnt/etc/initramfs-tools" ]]; then
    log "System does not use initramfs-tools, skipping F2FS module addition"
    return 0
  fi

  local has_initramfs=0
  if ls "$boot_dir"/initrd.img-* &>/dev/null || ls "$boot_dir"/initramfs-* &>/dev/null; then
    has_initramfs=1
  fi
  if ((has_initramfs == 0)); then
    log "No initramfs found in /boot, skipping F2FS module addition"
    return 0
  fi

  log "Adding F2FS module to initramfs..."
  if [[ ! -f $initramfs_modules ]]; then
    mkdir -p "$(dirname "$initramfs_modules")"
    echo "f2fs" >"$initramfs_modules"
    log "Created $initramfs_modules with F2FS module"
  elif ! grep -q "^f2fs$" "$initramfs_modules" 2>/dev/null; then
    echo "f2fs" >>"$initramfs_modules"
    log "Added F2FS to existing $initramfs_modules"
  else
    log "F2FS module already present in initramfs modules"
  fi

  touch "$root_mnt/.regenerate_initramfs"
  log "Marked for initramfs regeneration (run dietpi-chroot.sh on the output image)"
}

check_f2fs_support() {
  local root_mnt="$1"
  log "Checking F2FS kernel support..."

  local has_f2fs=0
  local modules_dir="$root_mnt/lib/modules"
  if [[ -d $modules_dir ]] && find "$modules_dir" -name "f2fs.ko*" 2>/dev/null | grep -q .; then
    has_f2fs=1
    log "F2FS module found in cloned kernel modules"
  fi

  if ((has_f2fs == 0)); then
    if [[ -f /proc/filesystems ]] && grep -q "f2fs" /proc/filesystems; then
      has_f2fs=1
      log "F2FS supported on host system"
    elif modinfo f2fs &>/dev/null; then
      has_f2fs=1
      log "F2FS module available on host"
    fi
  fi

  if ((has_f2fs == 0)); then
    warn "F2FS support not detected in kernel"
    warn "Image may fail to boot if the target kernel lacks F2FS support"
  else
    log "F2FS support verified"
  fi
}

detect_dietpi() {
  IS_DIETPI=0
  DIETPI_VERSION=""
  PI_MODEL=""

  if [[ -f "$DST_MNT_BOOT/dietpi/.version" || -f "$DST_MNT_BOOT/dietpi.txt" ]]; then
    IS_DIETPI=1
    [[ -f "$DST_MNT_BOOT/dietpi/.version" ]] && DIETPI_VERSION=$(head -1 "$DST_MNT_BOOT/dietpi/.version")

    if [[ -f "$DST_MNT_BOOT/config.txt" ]]; then
      if grep -qi "2712" "$DST_MNT_BOOT/config.txt" 2>/dev/null; then
        PI_MODEL="Raspberry Pi 5"
      elif grep -qi "2711" "$DST_MNT_BOOT/config.txt" 2>/dev/null; then
        PI_MODEL="Raspberry Pi 4"
      elif grep -qi "2837" "$DST_MNT_BOOT/config.txt" 2>/dev/null; then
        PI_MODEL="Raspberry Pi 3"
      else
        PI_MODEL="Raspberry Pi (unknown model)"
      fi
    fi

    log "Detected DietPi installation: v${DIETPI_VERSION:-unknown}"
    log "Hardware: ${PI_MODEL:-unknown}"
  fi
}

backup_dietpi_configs() {
  ((IS_DIETPI)) || return 0

  mkdir -p "$BACKUP_DIR"
  log "Backing up critical DietPi configs to $BACKUP_DIR..."

  [[ -f "$DST_MNT_BOOT/dietpi/.installed" ]] && cp "$DST_MNT_BOOT/dietpi/.installed" "$BACKUP_DIR/" 2>/dev/null || :
  [[ -f "$DST_MNT_BOOT/dietpi.txt" ]] && cp "$DST_MNT_BOOT/dietpi.txt" "$BACKUP_DIR/" 2>/dev/null || :
  [[ -f "$DST_MNT_ROOT/etc/network/interfaces" ]] && cp "$DST_MNT_ROOT/etc/network/interfaces" "$BACKUP_DIR/" 2>/dev/null || :
  [[ -d "$DST_MNT_ROOT/etc/wpa_supplicant" ]] && cp -r "$DST_MNT_ROOT/etc/wpa_supplicant" "$BACKUP_DIR/" 2>/dev/null || :
  [[ -f "$DST_MNT_ROOT/etc/hostname" ]] && cp "$DST_MNT_ROOT/etc/hostname" "$BACKUP_DIR/" 2>/dev/null || :
  [[ -f "$DST_MNT_ROOT/etc/hosts" ]] && cp "$DST_MNT_ROOT/etc/hosts" "$BACKUP_DIR/" 2>/dev/null || :

  log "Backup complete: $BACKUP_DIR"
}

verify_conversion() {
  log "Verifying F2FS conversion..."
  local errors=0

  local fstab="$DST_MNT_ROOT/etc/fstab"
  if [[ -f $fstab ]] && grep -q "f2fs" "$fstab"; then
    log "fstab contains F2FS root entry"
  else
    warn "fstab missing F2FS entry"
    ((errors++)) || :
  fi

  local cmdline="$DST_MNT_BOOT/cmdline.txt"
  if [[ -f $cmdline ]] && grep -q "rootfstype=f2fs" "$cmdline"; then
    log "cmdline.txt has rootfstype=f2fs"
  else
    warn "cmdline.txt missing rootfstype=f2fs"
    ((errors++)) || :
  fi

  if mountpoint -q "$DST_MNT_ROOT"; then
    log "F2FS root partition is mounted"
  else
    warn "Root partition not mounted"
    ((errors++)) || :
  fi

  printf '\n%b%s%b\n' "$B" "=== Conversion Summary ===" "$X"
  ((IS_DIETPI)) && printf '%b%-30s%b %s\n' "$G" "DietPi Version:" "$X" "${DIETPI_VERSION:-unknown}"
  ((IS_DIETPI)) && printf '%b%-30s%b %s\n' "$G" "Hardware:" "$X" "${PI_MODEL:-unknown}"
  printf '%b%-30s%b %s\n' "$G" "Root Filesystem:" "$X" "F2FS"
  [[ -n ${BACKUP_DIR:-} && -d ${BACKUP_DIR:-} ]] && printf '%b%-30s%b %s\n' "$G" "Backup Location:" "$X" "$BACKUP_DIR"
  printf '%b%s%b\n\n' "$B" "=========================" "$X"

  if ((errors > 0)); then
    warn "Conversion completed with $errors warning(s); review above"
  else
    log "All verification checks passed"
  fi
}

# --- Defaults & CLI ---
SRC_URL="$DIETPI_URL"
OUT_IMG="./DietPi_RPi234-ARMv8-Trixie_f2fs.img"
OUTPUT_DEVICE=""
ROOT_LABEL="dietpi-root"
ROOT_OPTS="compress_algorithm=zstd,compress_chksum,atgc,gc_merge,background_gc=on,lazytime"
INTERACTIVE=0
DRY_RUN=0
SHRINK=0
SSH_ENABLE=0
NO_USB_CHECK=0
NO_SIZE_CHECK=0
IS_DIETPI=0
BACKUP_DIR=""

while (($#)); do
  case "$1" in
    --src)
      SRC_URL="${2:-}"
      shift 2
      ;;
    --out)
      OUT_IMG="${2:-}"
      shift 2
      ;;
    --device)
      OUTPUT_DEVICE="${2:-}"
      OUT_IMG=""
      shift 2
      ;;
    --root-label)
      ROOT_LABEL="${2:-}"
      shift 2
      ;;
    --root-opts)
      ROOT_OPTS="${2:-}"
      shift 2
      ;;
    --shrink)
      SHRINK=1
      shift
      ;;
    --ssh)
      SSH_ENABLE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-usb-check)
      NO_USB_CHECK=1
      shift
      ;;
    --no-size-check)
      NO_SIZE_CHECK=1
      shift
      ;;
    -i | --interactive)
      INTERACTIVE=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown arg: $1" ;;
  esac
done

((EUID == 0)) || die "Root required"

if ((INTERACTIVE)); then
  select_source
  select_output
fi

need curl
need xz
need losetup
need parted
need rsync
need blkid
need mount
need umount
need mkfs.f2fs
need e2fsck
need resize2fs
need sed
need grep
need awk
need lsblk
need flock
need blockdev
need partprobe
if ((SHRINK)); then
  need tune2fs
  need truncate
fi
if ((INTERACTIVE)); then
  need fzf
fi

[[ $SRC_URL == "dietpi" ]] && SRC_URL="$DIETPI_URL"

# --- Lock target so concurrent runs can't race on the same device/image ---
if [[ -n $OUTPUT_DEVICE ]]; then
  LOCK_KEY="$OUTPUT_DEVICE"
else
  LOCK_KEY="$(readlink -f -- "$OUT_IMG" 2>/dev/null || printf '%s' "$OUT_IMG")"
fi
LOCK="/run/lock/f2fs-convert-${LOCK_KEY//\//_}.lock"
mkdir -p "${LOCK%/*}"
exec {LOCK_FD}>"$LOCK"
flock -n "$LOCK_FD" || die "Target locked by another run: $LOCK_KEY"

if [[ -n $OUTPUT_DEVICE ]]; then
  [[ -b $OUTPUT_DEVICE ]] || die "Device not found: $OUTPUT_DEVICE"
  if ((! NO_USB_CHECK)); then
    TRAN="$(lsblk -dno TRAN "$OUTPUT_DEVICE" 2>/dev/null || true)"
    [[ $TRAN =~ ^(usb|mmc)$ ]] || die "$OUTPUT_DEVICE is not USB/MMC transport (use --no-usb-check to force)"
  fi
fi

if ((DRY_RUN)); then
  msg "Dry run — no changes will be made."
  msg "  Source:      $SRC_URL"
  if [[ -n $OUTPUT_DEVICE ]]; then
    msg "  Target:      device $OUTPUT_DEVICE"
  else
    msg "  Target:      image $OUT_IMG"
  fi
  msg "  Root label:  $ROOT_LABEL"
  msg "  Root opts:   $ROOT_OPTS"
  msg "  Shrink:      $((SHRINK))"
  msg "  Enable SSH:  $((SSH_ENABLE))"
  exit 0
fi

WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

if [[ -n $OUTPUT_DEVICE ]]; then
  BACKUP_DIR="/var/tmp/f2fs-convert-backup-$(date +%Y%m%d-%H%M%S)"
else
  BACKUP_DIR="$(dirname -- "$(readlink -f -- "$OUT_IMG")")/f2fs-convert-backup-$(date +%Y%m%d-%H%M%S)"
fi

# --- Resolve source (URL or local file) into a private working copy ---
if [[ $SRC_URL =~ ^https:// ]]; then
  src_archive="${SRC_URL##*/}"
  log "Downloading: $SRC_URL"
  curl -fL --retry 5 --retry-delay 2 -o "$src_archive" "$SRC_URL"

  if [[ $src_archive == *.xz ]]; then
    log "Decompressing xz..."
    xz -dk "$src_archive"
    SRC_IMG="${src_archive%.xz}"
    [[ -f $SRC_IMG ]] || die "Decompressed .img not found: $SRC_IMG"
  else
    SRC_IMG="$src_archive"
  fi
elif [[ $SRC_URL =~ ^http:// ]]; then
  die "Insecure HTTP source not allowed; use an https:// URL"
elif [[ -f $SRC_URL ]]; then
  log "Using local file: $SRC_URL"
  if [[ $SRC_URL == *.xz ]]; then
    log "Decompressing xz..."
    xz -dc -- "$SRC_URL" >"source.img"
  else
    cp --reflink=auto -- "$SRC_URL" "source.img" 2>/dev/null || cp -- "$SRC_URL" "source.img"
  fi
  SRC_IMG="source.img"
else
  die "Source not found: $SRC_URL"
fi

((SHRINK)) && shrink_src_image

# --- Prepare output destination ---
if [[ -n $OUTPUT_DEVICE ]]; then
  if ((! NO_SIZE_CHECK)); then
    SRC_SZ="$(stat -c%s "$SRC_IMG")"
    DST_SZ="$(blockdev --getsize64 "$OUTPUT_DEVICE")"
    ((SRC_SZ <= DST_SZ)) || die "Source image ($SRC_SZ bytes) larger than target device ($DST_SZ bytes); use --no-size-check to override"
  fi
  log "Flashing source image to device: $OUTPUT_DEVICE"
  dd if="$SRC_IMG" of="$OUTPUT_DEVICE" bs=4M conv=fsync status=progress || die "dd failed writing to $OUTPUT_DEVICE"
  sync
  OUT_IMG="$OUTPUT_DEVICE"
else
  OUT_IMG="$(readlink -f -- "$OUT_IMG")"
  log "Copying to output image: $OUT_IMG"
  cp -f -- "$SRC_IMG" "$OUT_IMG"
fi

# --- Attach both images (source read-only, destination writable) ---
LOOP_SRC="$(losetup --find --show --partscan --read-only "$SRC_IMG")"
LOOP_DST="$(losetup --find --show --partscan "$OUT_IMG")"
log "Source loop: $LOOP_SRC"
log "Dest loop:   $LOOP_DST"

SRC_BOOT="${LOOP_SRC}p1"
SRC_ROOT="${LOOP_SRC}p2"
DST_BOOT="${LOOP_DST}p1"
DST_ROOT="${LOOP_DST}p2"
[[ -b $SRC_BOOT && -b $SRC_ROOT ]] || die "Source partitions missing (expected p1,p2)"
[[ -b $DST_BOOT && -b $DST_ROOT ]] || die "Dest partitions missing (expected p1,p2)"

SRC_ROOT_TYPE="$(blkid -o value -s TYPE "$SRC_ROOT" || true)"
DST_ROOT_TYPE="$(blkid -o value -s TYPE "$DST_ROOT" || true)"
[[ $SRC_ROOT_TYPE == "ext4" ]] || die "Expected source rootfs ext4, got: ${SRC_ROOT_TYPE:-unknown}"
[[ $DST_ROOT_TYPE == "ext4" ]] || die "Expected dest rootfs ext4 before conversion, got: ${DST_ROOT_TYPE:-unknown}"

GEOM="$(read_part_geom "$LOOP_DST" 2)"
[[ -n $GEOM ]] || die "Failed reading dest partition 2 geometry"
read -r ROOT_START ROOT_END <<<"$GEOM"
log "Dest root geometry (sectors): start=$ROOT_START end=$ROOT_END"

SRC_MNT_BOOT="$WORKDIR/src_boot"
SRC_MNT_ROOT="$WORKDIR/src_root"
domount "$SRC_BOOT" "$SRC_MNT_BOOT"
domount "$SRC_ROOT" "$SRC_MNT_ROOT" -o ro

DST_MNT_ROOT="$WORKDIR/dst_root"
DST_MNT_BOOT="$WORKDIR/dst_boot"
domount "$DST_BOOT" "$DST_MNT_BOOT"

log "e2fsck/resize2fs preflight on dest ext4 root..."
e2fsck -fy "$DST_ROOT" >/dev/null || :
resize2fs -M "$DST_ROOT" >/dev/null || :

log "Recreating dest partition 2 as f2fs..."
parted -s "$LOOP_DST" rm 2
parted -s "$LOOP_DST" unit s mkpart primary "$ROOT_START" "$ROOT_END"
partprobe "$LOOP_DST" || true

losetup -d "$LOOP_DST" &>/dev/null
LOOP_DST="$(losetup --find --show --partscan "$OUT_IMG")"
DST_BOOT="${LOOP_DST}p1"
DST_ROOT="${LOOP_DST}p2"
[[ -b $DST_ROOT ]] || die "Dest root partition missing after recreate: $DST_ROOT"

log "Formatting dest root as f2fs (label=$ROOT_LABEL)..."
mkfs.f2fs -f -l "$ROOT_LABEL" -O extra_attr,inode_checksum,sb_checksum,compression "$DST_ROOT" >/dev/null

log "Mounting dest f2fs root..."
domount "$DST_ROOT" "$DST_MNT_ROOT"

log "Copying rootfs ext4 -> f2fs (rsync)..."
rsync -aHAX --numeric-ids --info=progress2 \
  --exclude='/dev/*' --exclude='/proc/*' --exclude='/sys/*' --exclude='/run/*' --exclude='/tmp/*' \
  "$SRC_MNT_ROOT"/ "$DST_MNT_ROOT"/

detect_dietpi
backup_dietpi_configs
check_f2fs_support "$DST_MNT_ROOT"

remove_ext4_configs "$DST_MNT_ROOT"
add_f2fs_to_initramfs "$DST_MNT_ROOT"

# --- Patch fstab (root fstype -> f2fs; preserves existing UUID/PARTUUID/device refs) ---
FSTAB="$DST_MNT_ROOT/etc/fstab"
if [[ -f $FSTAB ]]; then
  log "Patching /etc/fstab root fstype -> f2fs..."
  awk '
    BEGIN{OFS="\t"}
    $0 ~ /^[[:space:]]*#/ {print; next}
    NF < 4 {print; next}
    $2 == "/" {$3="f2fs"; print; next}
    {print}
  ' "$FSTAB" >"$FSTAB.tmp" && mv -f -- "$FSTAB.tmp" "$FSTAB"
fi

# --- Patch cmdline.txt in dest /boot ---
CMDLINE="$DST_MNT_BOOT/cmdline.txt"
[[ -f $CMDLINE ]] || die "Missing dest cmdline.txt: $CMDLINE"

ROOT_UUID="$(blkid -o value -s UUID "$DST_ROOT")"
[[ -n ${ROOT_UUID:-} ]] || die "Failed to read UUID of dest f2fs root"

log "Patching /boot/cmdline.txt root=UUID=..., rootfstype=f2fs, rootflags=..."
CMD="$(<"$CMDLINE")"
CMD="${CMD//$'\n'/ }"

CMD="$(sed -E "s/(^|[[:space:]])root=[^[:space:]]+/\1root=UUID=${ROOT_UUID}/" <<<"$CMD")"
if grep -qE '(^|[[:space:]])rootfstype=' <<<"$CMD"; then
  CMD="$(sed -E 's/(^|[[:space:]])rootfstype=[^[:space:]]+/\1rootfstype=f2fs/' <<<"$CMD")"
else
  CMD+=" rootfstype=f2fs"
fi
if grep -qE '(^|[[:space:]])rootflags=' <<<"$CMD"; then
  CMD="$(sed -E "s/(^|[[:space:]])rootflags=[^[:space:]]+/\1rootflags=${ROOT_OPTS}/" <<<"$CMD")"
else
  CMD+=" rootflags=${ROOT_OPTS}"
fi

printf '%s\n' "$CMD" >"$CMDLINE"

# f2fs-tools provides fsck.f2fs; required by systemd-fsck@.service on first boot
if [[ ! -x "$DST_MNT_ROOT/sbin/fsck.f2fs" && ! -x "$DST_MNT_ROOT/usr/sbin/fsck.f2fs" ]]; then
  log "fsck.f2fs not found — attempting to install f2fs-tools into rootfs..."
  if ! chroot "$DST_MNT_ROOT" apt-get install -y --no-install-recommends f2fs-tools 2>/dev/null; then
    warn "f2fs-tools install failed. Boot should still work; fsck service (if any) may complain."
  fi
fi

if ((SSH_ENABLE)); then
  touch "$DST_MNT_BOOT/ssh"
  log "SSH enabled (touch /boot/ssh)"
fi

verify_conversion

sync
umount -R "$DST_MNT_ROOT"
umount -R "$DST_MNT_BOOT"
umount -R "$SRC_MNT_ROOT"
umount -R "$SRC_MNT_BOOT"
MOUNTS=()

log "Done."

if [[ -n $OUTPUT_DEVICE ]]; then
  log "Flashed to device: $OUTPUT_DEVICE"
  log "Next steps:"
  log "  1. Remove SD card and insert into Raspberry Pi"
  log "  2. Optional: Run dietpi-chroot.sh on mounted card to regenerate initramfs"
  log "  3. Boot with HDMI/serial console ready"
else
  log "Output image: $OUT_IMG"
  log "Next steps:"
  log "  1. Optional: sudo ./RaspberryPi/dietpi-chroot.sh '$OUT_IMG'"
  log "  2. Flash: sudo dd if='$OUT_IMG' of=/dev/mmcblk0 bs=4M conv=fsync status=progress"
  log "  3. Boot with HDMI/serial console ready"
fi

log ""
log "First boot notes:"
log "  - Have HDMI/serial console ready for debugging"
log "  - If kernel panic occurs, check F2FS module availability"
log "  - Run 'lsmod | grep f2fs' after boot to verify module loaded"
