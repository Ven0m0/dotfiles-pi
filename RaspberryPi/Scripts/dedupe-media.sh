#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'
export LC_ALL=C
# dedupe-media — whiptail + fzf TUI (and flag-driven CLI) to find/remove duplicate files
# (any type, including images and video) and to run optional lossless optimization /
# ffmpeg-based conversion: oxipng, jpegoptim, cwebp, qpdf, mp3->opus, mp4 audio->opus,
# mp4 video->h265/av1/vp9. Prefers ffzap over ffmpeg when present, silent fallback otherwise.
has() { command -v -- "$1" &>/dev/null; }
load_dietpi_globals() { [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :; }
load_dietpi_globals

# Colors
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' DEF=$'\e[0m' BLD=$'\e[1m'
log() { printf '%b\n' "${GRN}▶${DEF} $*"; }
warn() { printf '%b\n' "${YLW}⚠${DEF} $*" >&2; }
err() { printf '%b\n' "${RED}✗${DEF} $*" >&2; }
die() {
  err "$1"
  exit "${2:-1}"
}

WT_BACKTITLE="dedupe-media — duplicate finder & lossless media optimizer"
FZF_THEME=(--border=rounded --pointer='▶' --marker='✓' --info=inline
  --color="border:cyan,pointer:cyan,marker:green,header:yellow:bold,prompt:cyan:bold,fg+:bold")
fzf_themed() { fzf "${FZF_THEME[@]}" "$@"; }

require_tool() {
  local tool="$1" hint="${2:-$1}"
  has "$tool" || die "'${tool}' not found — install with: sudo apt-get install -y ${hint}"
}

# Config
declare -A cfg=(
  [recursive]=1 [min_size]=1 [include_empty]=0
  [dry_run]=0 [apply]=0 [action]=quarantine [replace]=0
  [jobs]=1 [audio_bitrate]=128k [video_codec]=h265 [interactive]=1
)
DIRS=()
REPORT_FILE=""
cleanup() {
  # Under `set -e`, an EXIT trap's own exit status can override the script's real
  # exit status, so this must never end on a failing test — always return 0.
  [[ -n $REPORT_FILE && -f $REPORT_FILE ]] && rm -f -- "$REPORT_FILE"
  return 0
}
trap cleanup EXIT

has nproc && cfg[jobs]=$(nproc)

usage() {
  cat <<'EOF'
dedupe-media.sh - find/remove duplicate files and losslessly optimize media

Usage: dedupe-media.sh [OPTIONS] [ACTIONS]
No ACTIONS given -> launches the whiptail+fzf TUI (requires both installed).

Scope options:
  -C, --dir PATH          Target directory (repeatable; default: current directory)
      --no-recursive      Don't descend into subdirectories
      --min-size BYTES    Skip files smaller than this (default: 1)
      --include-empty     Include zero-byte files in the dedup scan

Dedup actions:
      --scan               Report duplicate groups (dry-run; default when no action given)
      --apply              Act on duplicates found by the scan
      --action ACTION      delete | quarantine (default: quarantine)
      --keep-strategy S    oldest | newest | shortest-path (default: oldest; --apply only)
      --quarantine-dir DIR Where quarantined files go (default: <dir>/.dedupe-quarantine/<ts>/)

Conversion actions (each is independent and opt-in):
      --convert-png         Lossless PNG recompress via oxipng
      --convert-jpeg        Lossless JPEG recompress via jpegoptim
      --convert-webp        Lossless PNG/JPEG -> WebP via cwebp (writes alongside source)
      --convert-pdf         Lossless PDF recompress via qpdf
      --convert-mp3-opus    MP3 -> Opus (see --audio-bitrate)
      --convert-mp4-audio   MP4 audio track -> Opus, video stream copied (no re-encode)
      --convert-mp4-video   Re-encode MP4 video track (see --video-codec)
      --audio-bitrate BR    Opus bitrate (default: 128k)
      --video-codec CODEC   h265 | av1 | vp9 (default: h265; see --help-codecs)
      --replace              Replace source file after a successful conversion (default: keep both)

General:
  -j, --jobs N             Parallel conversion jobs (default: nproc)
  -y, --yes                Non-interactive, assume yes to prompts
  -d, --dry-run             Preview only, even for --apply/--convert-* (default for dedup)
      --help-codecs          Print the h265/av1/vp9 tradeoff summary and exit
  -h, --help                 Show this help

Video codec recommendation (Pi 4, software encode only): h265 (libx265) is the default —
best balance of compression and encode time, and the only one of the three with hardware
DECODE support on the Pi 4 itself. av1 compresses ~25-30% better but is far slower to
encode in software; vp9 is not recommended (worse compression than h265, no speed win).
Run --help-codecs for the full summary.
EOF
}

help_codecs() {
  cat <<'EOF'
Video codec tradeoffs for archival storage on a Raspberry Pi 4 (software encode only —
the Pi 4 has no hardware encoder for any of these three codecs):

  h265 (libx265)  [default]
    - Compression: baseline (roughly on par with or slightly ahead of vp9)
    - Encode speed: moderate; the fastest of the three high-efficiency options
    - Playback: Pi 4 has HARDWARE DECODE for h265 - smooth local playback
    - Recommended default: best balance for a device that both encodes and may play back

  av1 (libsvtav1, falls back to libaom-av1 if svt-av1 isn't built into ffmpeg)
    - Compression: ~25-30% smaller than h265/vp9 at equal quality
    - Encode speed: much slower in software - expect long batch/overnight jobs on a Pi 4
    - Playback: no hardware decode on the Pi 4 - CPU-bound playback too
    - Use when: maximum compression matters more than encode time or Pi-local playback

  vp9 (libvpx-vp9)
    - Compression: weakest of the three, roughly comparable to or behind h265
    - Encode speed: not meaningfully faster than h265 on this hardware in practice
    - Playback: no hardware decode on the Pi 4
    - Not recommended here - included for completeness/parity only
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
ACTIONS=()
parse_args() {
  while (($#)); do
    case "$1" in
      -C | --dir)
        DIRS+=("$2")
        shift
        ;;
      --no-recursive) cfg[recursive]=0 ;;
      --min-size)
        cfg[min_size]="$2"
        shift
        ;;
      --include-empty)
        cfg[include_empty]=1
        cfg[min_size]=0
        ;;
      --scan) ACTIONS+=(scan) ;;
      --apply)
        ACTIONS+=(scan)
        cfg[apply]=1
        cfg[dry_run]=0
        ;;
      --action)
        cfg[action]="$2"
        shift
        ;;
      --keep-strategy)
        cfg[keep_strategy]="$2"
        shift
        ;;
      --quarantine-dir)
        cfg[quarantine_dir]="$2"
        shift
        ;;
      --convert-png) ACTIONS+=(png) ;;
      --convert-jpeg) ACTIONS+=(jpeg) ;;
      --convert-webp) ACTIONS+=(webp) ;;
      --convert-pdf) ACTIONS+=(pdf) ;;
      --convert-mp3-opus) ACTIONS+=(mp3) ;;
      --convert-mp4-audio) ACTIONS+=(mp4a) ;;
      --convert-mp4-video) ACTIONS+=(mp4v) ;;
      --audio-bitrate)
        cfg[audio_bitrate]="$2"
        shift
        ;;
      --video-codec)
        cfg[video_codec]="$2"
        shift
        ;;
      --replace) cfg[replace]=1 ;;
      -j | --jobs)
        cfg[jobs]="$2"
        shift
        ;;
      -y | --yes) cfg[interactive]=0 ;;
      -d | --dry-run) cfg[dry_run]=1 ;;
      --help-codecs)
        help_codecs
        exit 0
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  ((${#DIRS[@]})) || DIRS=(".")
  local d
  for d in "${DIRS[@]}"; do
    [[ -d $d ]] || die "Not a directory: $d"
  done
}

# ---------------------------------------------------------------------------
# File collection
# ---------------------------------------------------------------------------
collect_files() {
  local -n _out=$1
  local d find_args=()
  ((cfg[recursive])) || find_args+=(-maxdepth 1)
  ((cfg[min_size] > 0)) && find_args+=(-size "+$((cfg[min_size] - 1))c")
  for d in "${DIRS[@]}"; do
    while IFS= read -r -d '' f; do
      _out+=("$f")
    done < <(find "$d" "${find_args[@]}" -type f -print0 2>/dev/null)
  done
}

# ---------------------------------------------------------------------------
# Hashing / dedup engine
# ---------------------------------------------------------------------------
select_hasher() {
  if has b3sum; then
    HASHER=(b3sum --no-names)
  elif has xxhsum; then
    HASHER=(xxhsum -H2)
  else
    HASHER=(sha256sum)
  fi
}
hash_file() { "${HASHER[@]}" -- "$1" 2>/dev/null | awk '{print $1; exit}'; }

# Populates REPORT_FILE with "<hash>\t<mtime>\t<size>\t<path>" lines, sorted so
# same-hash duplicate groups are contiguous. Only files whose duplicate group has
# more than one member are written.
scan_duplicates() {
  local -a files=() candidates=()
  local -A size_count=()
  collect_files files
  ((${#files[@]})) || {
    log "No files found under: $(IFS=' '; printf '%s' "${DIRS[*]}")"
    return 0
  }

  local size_tmp
  size_tmp="$(mktemp)"
  stat -c $'%s\t%n' -- "${files[@]}" 2>/dev/null >"$size_tmp"
  local size path
  while IFS=$'\t' read -r size path; do
    size_count["$size"]=$((${size_count["$size"]:-0} + 1))
  done <"$size_tmp"
  while IFS=$'\t' read -r size path; do
    ((${size_count["$size"]} > 1)) && candidates+=("$path")
  done <"$size_tmp"
  rm -f -- "$size_tmp"

  ((${#candidates[@]})) || {
    log "No same-size candidate files — nothing to dedupe."
    return 0
  }

  select_hasher
  log "Hashing ${#candidates[@]} same-size candidate file(s) with ${HASHER[0]}..."
  local hash_tmp
  hash_tmp="$(mktemp)"
  local file hash mtime fsize
  for file in "${candidates[@]}"; do
    hash="$(hash_file "$file")" || {
      warn "could not hash: $file"
      continue
    }
    [[ -n $hash ]] || continue
    mtime="$(stat -c%Y -- "$file" 2>/dev/null)" || continue
    fsize="$(stat -c%s -- "$file" 2>/dev/null)" || continue
    printf '%s\t%s\t%s\t%s\n' "$hash" "$mtime" "$fsize" "$file" >>"$hash_tmp"
  done

  REPORT_FILE="$(mktemp)"
  sort -t $'\t' -k1,1 "$hash_tmp" |
    awk -F'\t' '{c[$1]++; l[$1]=l[$1] $0 "\n"} END{for (h in c) if (c[h]>1) printf "%s", l[h]}' \
      >"$REPORT_FILE"
  rm -f -- "$hash_tmp"
}

report_duplicates() {
  [[ -s $REPORT_FILE ]] || {
    log "No duplicate files found."
    return 0
  }
  local groups wasted
  groups=$(cut -f1 "$REPORT_FILE" | sort -u | wc -l)
  wasted=$(awk -F'\t' '{sum[$1]+=$3; n[$1]++} END{t=0; for(h in sum) t += sum[h] - sum[h]/n[h]; printf "%.0f", t}' "$REPORT_FILE")
  log "${BLD}${groups}${DEF} duplicate group(s), ~${BLD}$((wasted / 1024 / 1024))MiB${DEF} reclaimable"
  awk -F'\t' '{printf "  %s  %8d bytes  %s\n", substr($1,1,10), $3, $4}' "$REPORT_FILE"
}

# Choose which file in a duplicate group to KEEP; prints the paths to REMOVE.
resolve_removals() {
  local strategy="${cfg[keep_strategy]:-oldest}"
  awk -F'\t' -v strat="$strategy" '
    {grp[$1] = grp[$1] $0 "\n"}
    END {
      for (h in grp) {
        n = split(grp[h], lines, "\n")
        keepIdx = 1
        for (i = 2; i <= n; i++) {
          if (lines[i] == "") continue
          split(lines[i], f, "\t")
          split(lines[keepIdx], kf, "\t")
          if (strat == "newest" && f[2]+0 > kf[2]+0) keepIdx = i
          else if (strat == "shortest-path" && length(f[4]) < length(kf[4])) keepIdx = i
          else if (strat != "newest" && strat != "shortest-path" && f[2]+0 < kf[2]+0) keepIdx = i
        }
        for (i = 1; i <= n; i++) {
          if (lines[i] == "" || i == keepIdx) continue
          split(lines[i], f, "\t")
          print f[4]
        }
      }
    }' "$REPORT_FILE"
}


# Path of $1 relative to whichever DIRS[] entry contains it, for use as a subpath
# under the quarantine dir (avoids reconstructing a full absolute path there).
relpath_under_dirs() {
  local f="$1" d
  for d in "${DIRS[@]}"; do
    case "$f" in
      "$d"/*)
        printf '%s\n' "${f#"$d"/}"
        return 0
        ;;
      "$d")
        basename -- "$f"
        return 0
        ;;
    esac
  done
  printf '%s\n' "${f#/}"
}

apply_removals() {
  local -a targets=("$@")
  ((${#targets[@]})) || {
    log "Nothing selected to remove."
    return 0
  }
  if ((cfg[dry_run])); then
    log "[DRY] Would ${cfg[action]} ${#targets[@]} file(s):"
    printf '  %s\n' "${targets[@]}"
    return 0
  fi
  local dest f rel
  case "${cfg[action]}" in
    delete)
      for f in "${targets[@]}"; do
        if rm -f -- "$f"; then
          log "deleted: $f"
        else
          warn "failed to delete: $f"
        fi
      done
      ;;
    quarantine)
      dest="${cfg[quarantine_dir]:-${DIRS[0]%/}/.dedupe-quarantine/$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)}"
      mkdir -p -- "$dest"
      for f in "${targets[@]}"; do
        rel="$(relpath_under_dirs "$f")"
        mkdir -p -- "$dest/$(dirname -- "$rel")"
        if mv -f -- "$f" "$dest/$rel"; then
          log "quarantined: $f -> $dest/$rel"
        else
          warn "failed to quarantine: $f"
        fi
      done
      ;;
    *) die "Unknown --action: ${cfg[action]} (expected delete|quarantine)" ;;
  esac
}

review_duplicates_fzf() {
  require_tool fzf
  [[ -s $REPORT_FILE ]] || {
    log "No duplicate files to review."
    return 0
  }
  local selection
  selection="$(
    sort -t $'\t' -k1,1 -k2,2n "$REPORT_FILE" |
      awk -F'\t' '{printf "%s\t%8d B\t%s\n", substr($1,1,10), $3, $4}' |
      fzf_themed --multi --delimiter=$'\t' --with-nth=1,2,3 \
        --header 'TAB to mark files for removal, ENTER to confirm, ESC to cancel' \
        --prompt 'remove> '
  )" || {
    log "Review cancelled — no changes made."
    return 0
  }
  [[ -n $selection ]] || {
    log "Nothing selected — no changes made."
    return 0
  }
  local -a targets=()
  while IFS=$'\t' read -r _ _ path; do
    [[ -n $path ]] && targets+=("$path")
  done <<<"$selection"
  apply_removals "${targets[@]}"
}

# ---------------------------------------------------------------------------
# Conversion: ffzap (preferred) with silent fallback to ffmpeg
# ---------------------------------------------------------------------------
run_ffmpeg_job() {
  local input="$1" output="$2"
  shift 2
  if has ffzap; then
    ffzap -i "$input" -f "$*" -o "$output" -t 1 &>/dev/null
  else
    ffmpeg -y -nostdin -loglevel error -i "$input" "$@" "$output"
  fi
}

run_parallel() {
  local func="$1"
  shift
  local -a targets=("$@")
  ((${#targets[@]})) || return 0
  local max="${cfg[jobs]}" running=0 f
  for f in "${targets[@]}"; do
    "$func" "$f" &
    running=$((running + 1))
    if ((running >= max)); then
      wait -n || :
      running=$((running - 1))
    fi
  done
  wait || :
}

convert_one_png() {
  local f="$1"
  if ((cfg[dry_run])); then
    log "[DRY] oxipng: $f"
    return 0
  fi
  oxipng -o max --strip safe -- "$f" &>/dev/null && log "optimized: $f" || warn "oxipng failed: $f"
}
convert_one_jpeg() {
  local f="$1"
  if ((cfg[dry_run])); then
    log "[DRY] jpegoptim: $f"
    return 0
  fi
  jpegoptim --strip-all -- "$f" &>/dev/null && log "optimized: $f" || warn "jpegoptim failed: $f"
}
convert_one_webp() {
  local f="$1" out="${1%.*}.webp"
  [[ -e $out ]] && return 0
  if ((cfg[dry_run])); then
    log "[DRY] cwebp (lossless) -> $out"
    return 0
  fi
  if cwebp -quiet -lossless -q 100 -- "$f" -o "$out" &>/dev/null; then
    log "converted: $f -> $out"
    if ((cfg[replace])); then rm -f -- "$f"; fi
  else
    warn "cwebp failed: $f"
  fi
}
convert_one_pdf() {
  local f="$1" tmp
  if ((cfg[dry_run])); then
    log "[DRY] qpdf (lossless recompress): $f"
    return 0
  fi
  tmp="$(mktemp --suffix=.pdf)"
  if qpdf --compression-level=9 --object-streams=generate --recompress-flate -- "$f" "$tmp" &>/dev/null; then
    mv -f -- "$tmp" "$f"
    log "recompressed: $f"
  else
    rm -f -- "$tmp"
    warn "qpdf failed: $f"
  fi
}
convert_one_mp3() {
  local f="$1" out="${1%.*}.opus"
  [[ -e $out ]] && return 0
  if ((cfg[dry_run])); then
    log "[DRY] mp3->opus (${cfg[audio_bitrate]}): $f -> $out"
    return 0
  fi
  if run_ffmpeg_job "$f" "$out" -c:a libopus -b:a "${cfg[audio_bitrate]}" -vn; then
    log "converted: $f -> $out"
    if ((cfg[replace])); then rm -f -- "$f"; fi
  else
    rm -f -- "$out"
    warn "mp3->opus failed: $f"
  fi
}
convert_one_mp4_audio() {
  local f="$1" out="${1%.*}.opus.${1##*.}"
  [[ -e $out ]] && return 0
  if ((cfg[dry_run])); then
    log "[DRY] mp4 audio->opus (${cfg[audio_bitrate]}): $f -> $out"
    return 0
  fi
  if run_ffmpeg_job "$f" "$out" -c:v copy -c:a libopus -b:a "${cfg[audio_bitrate]}"; then
    log "converted: $f -> $out"
    if ((cfg[replace])); then rm -f -- "$f"; fi
  else
    rm -f -- "$out"
    warn "mp4 audio->opus failed: $f"
  fi
}
convert_one_mp4_video() {
  local f="$1" codec="${cfg[video_codec]}" out="${1%.*}.${cfg[video_codec]}.${1##*.}"
  local -a vopts=()
  case "$codec" in
    h265) vopts=(-c:v libx265 -preset medium -crf 28) ;;
    av1)
      if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libsvtav1; then
        vopts=(-c:v libsvtav1 -preset 8 -crf 35)
      else
        vopts=(-c:v libaom-av1 -crf 30 -b:v 0 -cpu-used 4)
      fi
      ;;
    vp9) vopts=(-c:v libvpx-vp9 -crf 31 -b:v 0 -row-mt 1) ;;
    *) die "Unknown --video-codec: $codec (expected h265|av1|vp9)" ;;
  esac
  [[ -e $out ]] && return 0
  if ((cfg[dry_run])); then
    log "[DRY] mp4 video->${codec}: $f -> $out"
    return 0
  fi
  if run_ffmpeg_job "$f" "$out" "${vopts[@]}" -c:a libopus -b:a "${cfg[audio_bitrate]}"; then
    log "converted: $f -> $out"
    if ((cfg[replace])); then rm -f -- "$f"; fi
  else
    rm -f -- "$out"
    warn "mp4 video->${codec} failed: $f"
  fi
}

run_conversion() {
  local kind="$1" tool="$2" hint="$3" pattern="$4"
  require_tool "$tool" "$hint"
  local -a files=()
  local d
  local depth_args=()
  ((cfg[recursive])) || depth_args=(-maxdepth 1)
  for d in "${DIRS[@]}"; do
    while IFS= read -r -d '' f; do files+=("$f"); done < \
      <(find "$d" "${depth_args[@]}" -type f -iname "$pattern" -print0 2>/dev/null)
  done
  ((${#files[@]})) || {
    log "No ${kind} files found under: $(IFS=' '; printf '%s' "${DIRS[*]}")"
    return 0
  }
  log "Processing ${#files[@]} ${kind} file(s) (jobs=${cfg[jobs]})..."
  run_parallel "convert_one_${kind}" "${files[@]}"
}

# ---------------------------------------------------------------------------
# TUI
# ---------------------------------------------------------------------------
tui_pick_dir() {
  local d
  d=$(whiptail --backtitle "$WT_BACKTITLE" --title "Target directory" \
    --inputbox "Directory to scan/process:" 10 70 "${DIRS[0]:-.}" 3>&1 1>&2 2>&3) || return 1
  [[ -d $d ]] || {
    whiptail --msgbox "Not a directory: $d" 10 60
    return 1
  }
  DIRS=("$d")
}

tui_scan() {
  tui_pick_dir || return 0
  cfg[dry_run]=1
  scan_duplicates
  report_duplicates
}

tui_review() {
  tui_pick_dir || return 0
  scan_duplicates
  report_duplicates
  [[ -s $REPORT_FILE ]] || return 0
  cfg[dry_run]=0
  review_duplicates_fzf
}

tui_convert() {
  local kind="$1" label="$2"
  tui_pick_dir || return 0
  if whiptail --backtitle "$WT_BACKTITLE" --yesno "Run in dry-run (preview) mode first?" 10 60; then
    cfg[dry_run]=1
  else
    cfg[dry_run]=0
  fi
  case "$kind" in
    png) run_conversion png oxipng oxipng '*.png' ;;
    jpeg)
      run_conversion jpeg jpegoptim jpegoptim '*.jpg'
      run_conversion jpeg jpegoptim jpegoptim '*.jpeg'
      ;;
    webp)
      run_conversion webp cwebp webp '*.png'
      run_conversion webp cwebp webp '*.jpg'
      run_conversion webp cwebp webp '*.jpeg'
      ;;
    pdf) run_conversion pdf qpdf qpdf '*.pdf' ;;
    mp3) run_conversion mp3 ffmpeg ffmpeg '*.mp3' ;;
    mp4a) run_conversion mp4_audio ffmpeg ffmpeg '*.mp4' ;;
    mp4v) run_conversion mp4_video ffmpeg ffmpeg '*.mp4' ;;
  esac
  whiptail --msgbox "${label} pass complete. See terminal output above for details." 10 70
}

tui_main() {
  require_tool whiptail whiptail
  require_tool fzf fzf
  local choice
  while true; do
    choice=$(whiptail --backtitle "$WT_BACKTITLE" --title "dedupe-media" \
      --menu "Choose an action" 21 78 11 \
      scan "Scan for duplicate files (report only)" \
      review "Review & remove duplicates (fzf)" \
      png "Optimize PNG images (oxipng, lossless)" \
      jpeg "Optimize JPEG images (jpegoptim, lossless)" \
      webp "Convert PNG/JPEG to WebP (lossless)" \
      pdf "Compress PDFs losslessly (qpdf)" \
      mp3 "Convert MP3 to Opus" \
      mp4a "Convert MP4 audio track to Opus" \
      mp4v "Re-encode MP4 video (h265/av1/vp9)" \
      quit "Exit" \
      3>&1 1>&2 2>&3) || break
    case "$choice" in
      scan) tui_scan ;;
      review) tui_review ;;
      png) tui_convert png "PNG optimize" ;;
      jpeg) tui_convert jpeg "JPEG optimize" ;;
      webp) tui_convert webp "WebP convert" ;;
      pdf) tui_convert pdf "PDF compress" ;;
      mp3) tui_convert mp3 "MP3->Opus" ;;
      mp4a) tui_convert mp4a "MP4 audio->Opus" ;;
      mp4v) tui_convert mp4v "MP4 video re-encode" ;;
      quit | "") break ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"

  if ((${#ACTIONS[@]} == 0)); then
    tui_main
    return 0
  fi

  local action
  for action in "${ACTIONS[@]}"; do
    case "$action" in
      scan)
        scan_duplicates
        report_duplicates
        if ((cfg[apply])) && [[ -s $REPORT_FILE ]]; then
          mapfile -t removals < <(resolve_removals)
          log "keep-strategy=${cfg[keep_strategy]:-oldest}; ${#removals[@]} file(s) selected for ${cfg[action]}"
          apply_removals "${removals[@]}"
        fi
        ;;
      png) run_conversion png oxipng oxipng '*.png' ;;
      jpeg)
        run_conversion jpeg jpegoptim jpegoptim '*.jpg'
        run_conversion jpeg jpegoptim jpegoptim '*.jpeg'
        ;;
      webp)
        run_conversion webp cwebp webp '*.png'
        run_conversion webp cwebp webp '*.jpg'
        run_conversion webp cwebp webp '*.jpeg'
        ;;
      pdf) run_conversion pdf qpdf qpdf '*.pdf' ;;
      mp3) run_conversion mp3 ffmpeg ffmpeg '*.mp3' ;;
      mp4a) run_conversion mp4_audio ffmpeg ffmpeg '*.mp4' ;;
      mp4v) run_conversion mp4_video ffmpeg ffmpeg '*.mp4' ;;
    esac
  done
}

main "$@"
