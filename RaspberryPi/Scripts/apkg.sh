#!/usr/bin/env bash
# shellcheck enable=all shell=bash source-path=SCRIPTDIR
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "${SCRIPT_DIR}" && SCRIPT_DIR="$(pwd -P)" || exit 1
# apt-fuzz — whiptail + fzf TUI for apt/nala/apt-fast on Raspberry Pi/DietPi
# Features: whiptail-driven navigation, fzf fuzzy search w/ cached previews, multi-select,
#           backup/restore, prefetching, optional apt-fast bootstrap
# Inlined common functions
has() { command -v -- "$1" &>/dev/null; }
load_dietpi_globals() { [[ -f /boot/dietpi/func/dietpi-globals ]] && . "/boot/dietpi/func/dietpi-globals" &>/dev/null || :; }
load_dietpi_globals
# Colors
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' DEF=$'\e[0m' BLD=$'\e[1m'
log() { printf '%b\n' "${GRN}▶${DEF} $*"; }
warn() { printf '%b\n' "${YLW}⚠${DEF} $*" >&2; }
err() { printf '%b\n' "${RED}✗${DEF} $*" >&2; }

: "${XDG_CACHE_HOME:=${HOME}/.cache}"
CACHE_DIR="${XDG_CACHE_HOME%/}/apkg"
CACHE_INDEX="${CACHE_DIR}/.index"
: "${APT_FUZZ_CACHE_TTL:=86400}" "${APT_FUZZ_CACHE_MAX_BYTES:=52428800}" "${APT_FUZZ_PREFETCH_JOBS:=4}"
mkdir -p -- "${CACHE_DIR}" &>/dev/null
trap 'ps -o pid= --ppid=$$ 2>/dev/null | xargs -r kill 2>/dev/null; exit' EXIT SIGINT SIGTERM
# Tool detection
has fzf || { err "fzf is required (sudo apt-get install -y fzf) — aborting"; exit 1; }
has whiptail && HAS_WHIPTAIL=1 || HAS_WHIPTAIL=0
if has fd; then
  FIND_TOOL="fd"
  find_cache_files() { fd -0 -d 1 -tf . "${CACHE_DIR}" 2>/dev/null; }
elif has fdfind; then
  FIND_TOOL="fdfind"
  find_cache_files() { fdfind -0 -d 1 -tf . "${CACHE_DIR}" 2>/dev/null; }
else
  FIND_TOOL="find"
  find_cache_files() { find "${CACHE_DIR}" -maxdepth 1 -type f -print0 2>/dev/null; }
fi
FINDER_OPTS=(--layout=reverse-list --no-hscroll)
[[ -n ${APT_FUZZ_FINDER_OPTS:-} ]] && read -r -a FINDER_OPTS <<<"${APT_FUZZ_FINDER_OPTS}"
# Visual theme for the fzf screens (search/installed/upgradable — where fuzzy filtering and a
# live preview pane matter and whiptail can't keep up); whiptail owns the plain choice menus.
FZF_THEME=(--border=rounded --pointer='▶' --marker='✓' --info=inline
  --color="border:cyan,pointer:cyan,marker:green,header:yellow:bold,prompt:cyan:bold,fg+:bold")
fzf_themed() { fzf "${FINDER_OPTS[@]}" "${FZF_THEME[@]}" "$@"; }
WT_BACKTITLE="apt-fuzz — apt/nala/apt-fast TUI"

# Manager detection
declare -A MANAGERS=([apt]=1)
has nala && MANAGERS[nala]=1
has apt-fast && MANAGERS[apt-fast]=1
# Only auto-pick a fancier manager when the user hasn't explicitly requested one; otherwise
# honor their choice (previously nala/apt-fast silently overrode an explicit APT_FUZZ_MANAGER).
if [[ -n ${APT_FUZZ_MANAGER:-} ]]; then
  PRIMARY_MANAGER="$APT_FUZZ_MANAGER"
  if [[ -z ${MANAGERS[${PRIMARY_MANAGER}]:-} ]]; then
    warn "Unknown APT_FUZZ_MANAGER='${PRIMARY_MANAGER}'; falling back to apt-get"
    PRIMARY_MANAGER=apt-get
  fi
else
  PRIMARY_MANAGER=apt
  [[ -n ${MANAGERS[apt-fast]:-} ]] && PRIMARY_MANAGER=apt-fast
  [[ -n ${MANAGERS[nala]:-} ]] && PRIMARY_MANAGER=nala
fi
byte_to_human() {
  local bytes="${1:-0}" i=0 pow=1
  local -a units=(B K M G T)
  while [[ $bytes -ge $((pow * 1024)) && $i -lt 4 ]]; do
    pow=$((pow * 1024))
    i=$((i + 1))
  done
  local v10=$(((bytes * 10 + (pow / 2)) / pow))
  local w=$((v10 / 10)) d=$((v10 % 10))
  ((d > 0)) && printf '%d.%d%s\n' "$w" "$d" "${units[i]}" || printf '%d%s\n' "$w" "${units[i]}"
}
# Index-based cache management
_update_cache_index() {
  local tmp
  tmp=$(mktemp "${CACHE_INDEX}.XXXXXX")
  find_cache_files | xargs -0 -r stat -c '%n|%s|%Y' >"${tmp}" 2>/dev/null || :
  mv -f "${tmp}" "${CACHE_INDEX}"
}
_cache_info_from_index() { awk -F'|' 'BEGIN{t=f=o=0}{f++;t+=$2;if(!o||$3<o)o=$3}END{print t,f,o}' "${CACHE_INDEX}" 2>/dev/null || echo "0 0 0"; }
evict_old_cache() {
  [[ ! -s ${CACHE_INDEX} ]] && _update_cache_index
  [[ ! -s ${CACHE_INDEX} ]] && return
  local now limit="${APT_FUZZ_CACHE_MAX_BYTES}" del cutoff valid
  now=$(date +%s)
  cutoff=$((now - APT_FUZZ_CACHE_TTL))
  del=$(mktemp)
  valid=$(mktemp)
  trap 'rm -f "${del}" "${valid}"' RETURN
  awk -F'|' -v c="${cutoff}" '$3<c{print $1}' "${CACHE_INDEX}" >"${del}"
  awk -F'|' -v c="${cutoff}" '$3>=c' "${CACHE_INDEX}" >"${valid}"
  if ((limit > 0)) && [[ -s ${valid} ]]; then
    local total excess
    total=$(awk -F'|' '{s+=$2}END{print s+0}' "${valid}")
    if ((total > limit)); then
      excess=$((total - limit))
      sort -t'|' -k3,3n "${valid}" | awk -F'|' -v e="${excess}" 'BEGIN{d=0}d<e{print $1;d+=$2}' >>"${del}"
    fi
  fi
  xargs -r -a "${del}" rm -f --
  _update_cache_index
}
# Cache & preview
_cache_file_for() { printf '%s/%s.cache' "$CACHE_DIR" "${1//[^a-zA-Z0-9._+-]/_}"; }
_generate_preview() {
  local pkg="$1" out tmp
  out="$(_cache_file_for "$pkg")"
  tmp="${out}.tmp.$$"
  {
    apt-cache show "$pkg" 2>/dev/null || :
    printf '\n--- changelog (first 200 lines) ---\n'
    apt-get changelog "$pkg" 2>/dev/null | sed -n '1,200p' || :
  } >"$tmp" 2>/dev/null
  sed -i 's/\x1b\[[0-9;]*m//g' "$tmp" 2>/dev/null || :
  mv -f "$tmp" "$out"
  chmod 644 "$out" 2>/dev/null || :
}
_cached_preview_print() {
  local pkg="$1" f now mtime
  f="$(_cache_file_for "$pkg")"
  now=$(date +%s)
  mtime=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
  if ((now - mtime < APT_FUZZ_CACHE_TTL)); then
    cat "$f" 2>/dev/null || echo "(no preview)"
  else
    _generate_preview "$pkg"
    cat "$f" 2>/dev/null || echo "(no preview)"
  fi
}
export -f _cached_preview_print _cache_file_for _generate_preview
# Background prefetch
_prefetch_lists() {
  (apt-cache pkgnames >"$CACHE_DIR/pkgnames.list" 2>/dev/null) &
  (dpkg-query -W -f='${Package}\n' >"$CACHE_DIR/installed.list" 2>/dev/null) &
  (apt list --upgradable 2>/dev/null | awk -F/ 'NR>1{print $1}' >"$CACHE_DIR/upgradable.list") &
}
_prefetch_previews() {
  wait
  local i=0 pkg
  while IFS= read -r pkg; do
    ((i = i % APT_FUZZ_PREFETCH_JOBS, i++ == 0)) && wait
    _generate_preview "$pkg" &
  done < <(head -n 200 "$CACHE_DIR/installed.list" 2>/dev/null)
  wait
  _update_cache_index
}
# Package lists
list_all_packages() { [[ -f $CACHE_DIR/pkgnames.list ]] && cat "$CACHE_DIR/pkgnames.list" || apt-cache pkgnames; }
list_installed() { [[ -f $CACHE_DIR/installed.list ]] && cat "$CACHE_DIR/installed.list" || dpkg-query -W -f='${Package}\n'; }
list_upgradable() { [[ -f $CACHE_DIR/upgradable.list ]] && cat "$CACHE_DIR/upgradable.list" || apt list --upgradable 2>/dev/null | awk -F/ 'NR>1{print $1}'; }
# Manager runner
run_mgr() {
  local action="$1"
  shift
  local -a pkgs=("$@") cmd=()
  case "$PRIMARY_MANAGER" in
    nala)
      case "$action" in update | upgrade | autoremove | clean) cmd=(nala "$action" -y) ;; *) cmd=(nala "$action" -y "${pkgs[@]}") ;; esac
      ;;
    apt-fast)
      case "$action" in update | upgrade | autoremove | clean) cmd=(apt-fast "$action" -y) ;; *) cmd=(apt-fast "$action" -y "${pkgs[@]}") ;; esac
      ;;
    *)
      case "$action" in
        update | upgrade | autoremove | clean) cmd=(apt-get "$action" -y) ;;
        install | remove | purge) cmd=(apt-get "$action" -y "${pkgs[@]}") ;;
        *) cmd=(apt "$action" "${pkgs[@]}") ;;
      esac
      ;;
  esac
  printf 'Running: sudo %s\n' "${cmd[*]}"
  # DEBIAN_FRONTEND doesn't survive sudo's environment reset when merely set in this shell, so
  # route it through env, which sets it directly for the exec'd process (was previously dropped,
  # risking interactive debconf prompts mid-install).
  sudo env DEBIAN_FRONTEND=noninteractive "${cmd[@]}"
}
# Bootstraps apt-fast via its PPA + keyring (mirrors setup.sh's install_package_managers()).
_install_apt_fast() {
  if has apt-fast; then
    printf 'apt-fast is already installed.\n'
    MANAGERS[apt-fast]=1
    return 0
  fi
  log "Installing apt-fast (PPA + keyring)"
  sudo install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
  curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xBC5934FD3DEBD4DAEA544F791E2824A7F22B44BD" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/apt-fast.gpg
  echo "deb [signed-by=/etc/apt/keyrings/apt-fast.gpg] http://ppa.launchpad.net/apt-fast/stable/ubuntu focal main" \
    | sudo tee /etc/apt/sources.list.d/apt-fast.list >/dev/null
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update -y
  if sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y apt-fast; then
    MANAGERS[apt-fast]=1
    log "apt-fast installed"
  else
    warn "apt-fast install failed; continuing without it"
  fi
}
# --- Themed UI: whiptail primary, fzf fallback ------------------------------
# wt_menu TITLE PROMPT TAG1 ITEM1 [TAG2 ITEM2 ...]
# Prints the chosen TAG on stdout; prints nothing and returns 1 on cancel/Esc.
wt_menu() {
  local title="$1" prompt="$2"
  shift 2
  local -a args=("$@") tags=() items=()
  local i
  for ((i = 0; i < ${#args[@]}; i += 2)); do
    tags+=("${args[i]}")
    items+=("${args[i + 1]}")
  done
  local n=${#items[@]} choice height
  if ((HAS_WHIPTAIL)); then
    height=$((n < 1 ? 1 : (n < 10 ? n : 10)))
    choice=$(whiptail --backtitle "$WT_BACKTITLE" --title "$title" --menu "$prompt" 20 76 "$height" "${args[@]}" 3>&1 1>&2 2>&3) || return 1
  else
    choice=$(printf '%s\n' "${items[@]}" | fzf_themed --height=40% --prompt="${title}> " --header="$prompt") || return 1
    [[ -z $choice ]] && return 1
    for i in "${!items[@]}"; do
      [[ ${items[i]} == "$choice" ]] && { choice="${tags[i]}"; break; }
    done
  fi
  [[ -z $choice ]] && return 1
  printf '%s\n' "$choice"
}
# wt_input TITLE PROMPT [DEFAULT]
wt_input() {
  local title="$1" prompt="$2" default="${3:-}" val
  if ((HAS_WHIPTAIL)); then
    val=$(whiptail --backtitle "$WT_BACKTITLE" --title "$title" --inputbox "$prompt" 10 70 "$default" 3>&1 1>&2 2>&3) || return 1
  else
    read -r -p "${prompt} [${default}]: " val || return 1
    val="${val:-$default}"
  fi
  printf '%s\n' "$val"
}
choose_manager() {
  local -a items=(apt "apt (default APT frontend)")
  [[ -n ${MANAGERS[apt-fast]:-} ]] && items+=(apt-fast "apt-fast (parallel-download APT wrapper)")
  [[ -n ${MANAGERS[nala]:-} ]] && items+=(nala "nala (colorful, parallel-fetch APT frontend)")
  local choice
  choice=$(wt_menu "Package Manager" "Select the primary manager to use:" "${items[@]}") || return
  PRIMARY_MANAGER="$choice"
}
# UI helpers
_status_header() {
  local total files oldest age now size
  now=$(date +%s)
  read -r total files oldest < <(_cache_info_from_index)
  ((oldest == 0)) && age="0m" || age=$(((now - oldest) / 60))m
  size=$(byte_to_human "$total")
  printf 'manager: %s | finder: %s | cache: %s files, %s, oldest: %s' "$PRIMARY_MANAGER" "$FIND_TOOL" "$files" "$size" "$age"
}
action_menu_for_pkgs() {
  local -a pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return
  local choice
  choice=$(wt_menu "Action" "Choose an action for ${#pkgs[@]} package(s):" \
    Install "Install selected package(s)" \
    Remove "Remove selected package(s)" \
    Purge "Remove and purge configs" \
    Changelog "View changelog(s)" \
    Cancel "Back") || return
  case "$choice" in
    Install) run_mgr install "${pkgs[@]}" ;;
    Remove) run_mgr remove "${pkgs[@]}" ;;
    Purge) run_mgr purge "${pkgs[@]}" ;;
    Changelog) for p in "${pkgs[@]}"; do apt-get changelog "$p" 2>/dev/null | less; done ;;
    Cancel) return ;;
  esac
}
menu_search() {
  local sel
  sel=$(list_all_packages | fzf_themed --multi --height=60% --prompt="🔎 Search> " --header="$(_status_header)" \
    --preview="bash -c '_cached_preview_print {}'" --preview-window=right:60% --bind 'tab:toggle+down,ctrl-a:select-all,ctrl-d:deselect-all') || return
  [[ -z $sel ]] && return
  local -a pkgs
  mapfile -t pkgs <<<"$sel"
  action_menu_for_pkgs "${pkgs[@]}"
}
menu_installed() {
  local sel
  sel=$(list_installed | fzf_themed --multi --height=60% --prompt="📦 Installed> " --header="$(_status_header)" \
    --preview="bash -c '_cached_preview_print {}'" --preview-window=right:60% --bind 'tab:toggle+down,ctrl-a:select-all,ctrl-d:deselect-all') || return
  [[ -z $sel ]] && return
  local -a pkgs
  mapfile -t pkgs <<<"$sel"
  action_menu_for_pkgs "${pkgs[@]}"
}
menu_upgradable() {
  local sel
  sel=$(list_upgradable | fzf_themed --multi --height=40% --prompt="⬆ Upgradable> " --header="$(_status_header)" \
    --preview="bash -c '_cached_preview_print {}'" --preview-window=right:60% --bind 'tab:toggle+down,ctrl-a:select-all,ctrl-d:deselect-all') || return
  [[ -z $sel ]] && return
  local -a pkgs
  mapfile -t pkgs <<<"$sel"
  [[ ${#pkgs[@]} -gt 0 ]] && run_mgr install "${pkgs[@]}"
}
backup_installed() {
  local out="${1:-pkglist-$(date +%F).txt}"
  dpkg-query -W -f='${Package}\n' | sort -u >"$out"
  printf 'Saved: %s\n' "$out"
}
restore_from_file() {
  local file="$1"
  [[ ! -f $file ]] && {
    err "File not found: $file"
    return 1
  }
  local -a pkgs
  mapfile -t pkgs < <(sed '/^$/d' "$file")
  [[ ${#pkgs[@]} -eq 0 ]] && {
    printf 'No packages\n'
    return 0
  }
  local -a sel
  if ((HAS_WHIPTAIL)); then
    local -a wt_items=()
    local p raw
    for p in "${pkgs[@]}"; do wt_items+=("$p" "" OFF); done
    raw=$(whiptail --backtitle "$WT_BACKTITLE" --title "Restore" --checklist \
      "Select packages to install (SPACE to toggle, ENTER to confirm):" 20 76 12 "${wt_items[@]}" 3>&1 1>&2 2>&3) || return
    mapfile -t sel < <(grep -o '"[^"]*"' <<<"$raw" | tr -d '"')
  else
    mapfile -t sel < <(printf '%s\n' "${pkgs[@]}" | fzf_themed --multi --height=40% --prompt="Confirm install> ") || return
  fi
  [[ ${#sel[@]} -eq 0 ]] && return
  run_mgr install "${sel[@]}"
}
menu_backup_restore() {
  local choice
  choice=$(wt_menu "Backup / Restore" "$(_status_header)" \
    backup "Backup installed packages to a file" \
    restore "Restore packages from a file" \
    cancel "Back") || return
  case "$choice" in
    backup) backup_installed ;;
    restore)
      local f
      f=$(wt_input "Restore" "Path to package list file") || return
      [[ -n $f ]] && restore_from_file "$f"
      ;;
  esac
}
menu_maintenance() {
  local choice
  choice=$(wt_menu "Maintenance" "$(_status_header)" \
    update "Refresh package indexes" \
    upgrade "Upgrade all packages" \
    autoremove "Remove unused dependencies" \
    clean "Clear the local package cache" \
    apt-fast "Install apt-fast (parallel-download APT wrapper)" \
    manager "Choose primary manager" \
    cancel "Back") || return
  case "$choice" in
    update) run_mgr update ;;
    upgrade) run_mgr upgrade ;;
    autoremove) run_mgr autoremove ;;
    clean) run_mgr clean ;;
    apt-fast) _install_apt_fast ;;
    manager) choose_manager ;;
  esac
}
main_menu() {
  evict_old_cache
  local choice
  while choice=$(wt_menu "apt-fuzz" "$(_status_header)" \
    search "🔎 Search packages" \
    installed "📦 Installed" \
    upgradable "⬆ Upgradable" \
    backup "🗄 Backup / Restore" \
    maintenance "🛠 Maintenance" \
    manager "⚙ Choose manager" \
    quit "🚪 Quit"); do
    case "$choice" in
      search) menu_search ;;
      installed) menu_installed ;;
      upgradable) menu_upgradable ;;
      backup) menu_backup_restore ;;
      maintenance) menu_maintenance ;;
      manager) choose_manager ;;
      quit) break ;;
    esac
  done
}
_install_self() {
  local dest="${HOME}/.local/bin/apt-fuzz" compdir="${HOME}/.local/share/bash-completion/completions"
  mkdir -p -- "${HOME}/.local/bin"
  cp -f -- "$0" "$dest"
  chmod +x -- "$dest"
  printf 'Installed: %s\n' "$dest"
  mkdir -p -- "$compdir"
  cat >"$compdir/apt-fuzz" <<'COMP'
_complete_apt_fuzz(){
  local cur="${COMP_WORDS[COMP_CWORD]}" opts="search installed upgradable install remove purge backup restore maintenance choose-manager install-apt-fast quit"
  COMPREPLY=(); (( COMP_CWORD==1 )) && { COMPREPLY=( $(compgen -W "$opts" -- "$cur") ); return; }
  case "${COMP_WORDS[1]}" in
    install|remove|purge) local pkgnames=$(apt-cache pkgnames); COMPREPLY=( $(compgen -W "$pkgnames" -- "$cur") );;
    restore) COMPREPLY=( $(compgen -f -- "$cur") );;
  esac
}
complete -F _complete_apt_fuzz apt-fuzz
COMP
  printf 'Completion: %s/apt-fuzz\n' "$compdir"
}
_uninstall_self() {
  local dest="${HOME}/.local/bin/apt-fuzz" comp="${HOME}/.local/share/bash-completion/completions/apt-fuzz"
  printf 'Uninstalling...\n'
  rm -f -- "$dest" "$comp"
  rm -rf -- "$CACHE_DIR"
  printf 'Removed: %s\n%s\n%s\n' "$dest" "$comp" "$CACHE_DIR"
}
# Entry point
if (($# > 0)); then
  case "$1" in
    --install)
      _install_self
      exit 0
      ;;
    --uninstall)
      _uninstall_self
      exit 0
      ;;
    --install-apt-fast)
      _install_apt_fast
      exit 0
      ;;
    --preview)
      [[ -z ${2:-} ]] && {
        echo "usage: $0 --preview <pkg>" >&2
        exit 2
      }
      _cached_preview_print "$2"
      exit 0
      ;;
    install | remove | purge)
      [[ $# -lt 2 ]] && {
        echo "Usage: $0 $1 <pkgs...>" >&2
        exit 2
      }
      action="$1"
      shift
      run_mgr "$action" "$@"
      exit 0
      ;;
    help | -h | --help)
      cat <<EOF
Usage: $0 [--install|--uninstall|--install-apt-fast] | [install|remove|purge <pkgs...>] | [--preview <pkg>]
Run without args for the TUI (whiptail menus, fzf fuzzy search/installed/upgradable).
EOF
      exit 0
      ;;
  esac
fi
printf '%b\n' "${BLD}apt-fuzz${DEF}: whiptail navigation + fzf fuzzy package search for apt/nala/apt-fast"
printf 'Controls: menus = arrows/Enter/Esc | search/installed/upgradable = fuzzy-type, TAB multi-select, Enter confirm\n'
evict_old_cache
_prefetch_lists
_prefetch_previews &
main_menu
