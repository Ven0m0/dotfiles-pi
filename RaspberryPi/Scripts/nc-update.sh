#!/usr/bin/env bash
# shellcheck enable=all shell=bash
# Update Nextcloud core and apps, then run post-update DB/repair steps.
# Install: sudo install -m755 nc-update.sh /usr/local/bin/nc-update
# Usage:   sudo nc-update            (core + apps)
#          sudo NC_SKIP_CORE=1 nc-update   (apps only)
set -euo pipefail
IFS=$'\n\t' LC_ALL=C

NC_DIR=${NC_DIR:-/var/www/nextcloud}
cd "${NC_DIR}"
occ() { sudo -u www-data php "${NC_DIR}/occ" "$@"; }

# Updater runs `occ upgrade` itself. It keeps a backup under the data dir.
if [[ -z ${NC_SKIP_CORE:-} ]]; then
  sudo -u www-data php "${NC_DIR}/updater/updater.phar" --no-interaction
fi

occ app:update --all
occ db:add-missing-indices
occ db:add-missing-columns
occ db:add-missing-primary-keys
occ maintenance:repair --include-expensive
occ maintenance:mode --off

# Hand patch for upstream nextcloud/server#63229; a core update overwrites it.
grep -q 'p\.file_id' lib/private/Preview/Db/PreviewMapper.php ||
  echo "WARNING: PreviewMapper.php p.file_id patch missing, reapply" >&2
# setupchecks exits non-zero on warnings; report only.
# shellcheck disable=SC2310
occ setupchecks || true
