# Plan: pi4 Nextcloud + system optimization (multi-task)

## Context

`pi4` (`dietpi@192.168.178.81`, DietPi/Debian 13, Pi 8GB, kernel 6.18, aarch64)
runs the live stack **nginx + mariadb + php8.4 + redis** serving **Nextcloud
34.0.1** at `https://ven0m0.dpdns.org/nextcloud` via a **cloudflared tunnel**.
Data dir is the btrfs SSD `/mnt/nextcloud-ssd` (27 GB, subvol `@nextcloud-data`);
the MariaDB DB lives on the ext4 SD root (`/var/lib/mysql`). Primary NC user:
`ven0m0` (also `admin`, `jesper`).

This plan replaces the old Apache-only PLAN.md, **folding the Apache uninstall in**
as the final cleanup phase, and adds the requested work. Everything was verified
live over SSH. Ordering is safety-first: full backup snapshot **before** any
removal; all destructive steps last.

Verified facts that shape the plan:
- **Nextcloud Office is NOT working today.** Frontend `eurooffice` ("Nextcloud
  Office", enabled) has empty `wopi_url`/`public_wopi_url`; the built-in Collabora
  backend `richdocumentscode_arm64` (253 MB, "Collabora Online - Built-in CODE
  Server ARM64") is **disabled**; nothing listens on :9980. Fix = enable + wire the
  built-in server. It must be **kept**, not removed.
- **"File actions" = `files_scripts`** (enabled). It runs a sandboxed **Lua**
  interpreter exposing `shell_command`, `ffmpeg`, `file_content`, `new_file`,
  `get_input_files`, `get_parent`, `abort`, etc. (see
  `apps/files_scripts/lib/Interpreter/Functions/`). Host has `/usr/bin/ffmpeg`
  **with libwebp encoder** and PHP **GD with webp**. Existing script: "Merge PDFs".
  So image conversion is feasible via a Lua script shelling out to ffmpeg.
- **"Exclude directories" = `files_excludedirs`** (enabled). Exclude list is
  appconfig key `exclude` = `[".snapshot","*.tmp","node_modules",".venv","logs",".git"]`.
- **zram**: DietPi manages the active zram swap (3.8 GB, algorithm **zstd**). The
  redundant `zram-tools` unit `zramswap.service` is **failed** (device already in
  use). `fstrim.timer` enabled (weekly TRIM).
- **DNS**: `ven0m0.dpdns.org` is delegated to **Cloudflare** (`fred/daisy.ns.cloudflare.com`,
  proxied A records). The Google verification TXT must be added in **Cloudflare via
  API**, not on the pi. `bw` CLI is installed on the local Windows machine (not the
  pi); token is in Bitwarden secure note **"api-keys"**.
- **Google Keep**: 14 `.md` files in `Nextcloud2/obsidian-vault/GoogleKeep` (target
  `Notes/` folder is empty; NC `notesPath` = default "Notes").
- **apache2** 2.4.68 installed but inactive.

## Critical files / locations

- SSH: `~/.ssh/config` -> `pi4`. Run remote cmds via `ssh pi4 '...'` with `sudo`.
- Nextcloud: `/var/www/nextcloud` (occ, `config/config.php`); data `/mnt/nextcloud-ssd`;
  user files `/mnt/nextcloud-ssd/ven0m0/files/`.
- files_scripts API: `/var/www/nextcloud/apps/files_scripts/lib/Interpreter/Functions/`,
  examples in `apps/files_scripts/examples/*.lua`.
- fstab: `/etc/fstab`. zram: `/etc/default/zramswap`, `/sys/block/zram0/*`,
  `/boot/dietpi.txt` (`AUTO_SETUP_SWAPFILE_LOCATION=zram`).
- Local: `C:\Users\Ven0m0\Nextcloud2\obsidian-vault\GoogleKeep`,
  `C:\Users\Ven0m0\Nextcloud2\Notes`, `C:\Users\Ven0m0\Nextcloud2\google-dns-record.txt`
  (value `google-site-verification=3Wh2yEDdPRhd4aiVHb_SMccl1Sxh4jCdtodMwyLGOuk`).

---

## Phase 0 - Safety net (BEFORE any change; reused from old plan)

Backup dir `/mnt/data/Backup/pi4-optimize_$(date +%F_%H%M)/`, snapshot under
`/mnt/data/.snapshots/`.
1. `occ maintenance:mode --on`
2. Read-only btrfs snapshot: `btrfs subvolume snapshot -r /mnt/nextcloud-ssd /mnt/data/.snapshots/nextcloud-data_<ts>`
3. `mysqldump --single-transaction --routines --triggers --databases <dbname> > <dir>/nextcloud-db.sql` (root uses unix_socket; get dbname from config.php)
4. Config tarball: `tar czf <dir>/configs.tgz /etc/nginx /etc/php /etc/mysql /etc/fstab /etc/default/zramswap /var/www/nextcloud/config`
5. `occ maintenance:mode --off`
6. Verify snapshot listed, dump non-empty (ends with `Dump completed`), tarball present. **Abort all if any check fails.**

## Phase 1 - Make Nextcloud Office work (in-browser edit/view)

1. First read `apps/eurooffice/appinfo/info.xml` + admin settings route to confirm
   it drives the built-in-CODE flow like upstream `richdocuments`.
2. `occ app:enable richdocumentscode_arm64` (built-in ARM64 Collabora CODE).
3. Point the frontend at the built-in proxy (no extra port; works through the
   tunnel): set `wopi_url` to the built-in proxy URL
   `https://ven0m0.dpdns.org/nextcloud/apps/richdocumentscode_arm64/proxy.php?req=`
   (via the eurooffice admin UI "use built-in server" toggle, or
   `occ config:app:set eurooffice wopi_url --value ...`). Confirm `wopi_url` /
   `public_wopi_url` now populated.
4. Ensure `ven0m0.dpdns.org` in `wopi_allowlist` and NC `trusted_domains`.
5. **Verify in-browser editing** (the explicit ask): open a `.odt`/`.docx` in the
   web UI via browser automation (Claude-in-Chrome), confirm the Collabora editor
   loads and edits save. Watch coolwsd CPU on the Pi during the test; if the ARM64
   CODE server is too heavy, note external-Collabora as fallback (do not switch
   without asking).

## Phase 2 - Extend "Exclude directories" (files_excludedirs)

Append to the `exclude` JSON array (keep existing entries). Proposed additions
(confirm/trim during execution): `.git`, `.cache`, `__pycache__`, `.DS_Store`,
`Thumbs.db`, `.idea`, `.vscode`, `target`, `dist`, `build`, `.pytest_cache`,
`.mypy_cache`, `.ruff_cache`.
`occ config:app:set files_excludedirs exclude --value '[...merged JSON...]'`,
then verify with `config:app:get`.

## Phase 3 - Image conversion as "File actions" (files_scripts)

1. Read `Functions/Util/Shell_Command.php` and `Functions/Media/Ffmpeg.php` to get
   exact Lua signatures (how bytes/temp files are passed) and mirror `examples/merge_pdfs.lua`.
2. Author 3 Lua scripts (each becomes its own context-menu "File actions" entry),
   run ffmpeg for conversion (webp confirmed available):
   - **JPEG -> PNG**, **PNG -> JPEG**, **PNG/JPEG -> WebP**.
   - Pattern per script: `get_input_files()` -> for each, write bytes to temp ->
     `shell_command("ffmpeg -i in.<x> out.<y>")` (or the `ffmpeg` fn) -> read result
     -> `new_file(get_parent(f), "<name>.<ext>", content)`; skip non-matching input
     types; `abort` on collision.
3. Install via the files_scripts admin UI (Settings) or `occ files_scripts:import`.
4. Verify: `occ files_scripts:list` shows the 3 entries; browser-test the context
   menu on a sample jpg/png and confirm the converted file appears.

## Phase 4 - Google Keep -> Nextcloud Notes migration

Server-side (deterministic; avoids relying on the desktop client):
1. `scp` the note `.md` files (exclude the obsidian index `_about.md`) from
   `Nextcloud2/obsidian-vault/GoogleKeep` to `/mnt/nextcloud-ssd/ven0m0/files/Notes/`.
2. `chown -R www-data:www-data /mnt/nextcloud-ssd/ven0m0/files/Notes`
3. `occ files:scan --path="ven0m0/files/Notes"`
4. Verify the Notes app lists them (filenames become titles). No conversion needed
   (already markdown).

## Phase 5 - Google Search Console DNS TXT (Cloudflare API + Bitwarden)

Runs entirely on the **local Windows machine** (`bw` CLI is here, not the pi; the
pi is not involved in DNS at all).
1. `bw unlock` -> `bw get item "api-keys"` (or `bw get notes`), extract the
   **Cloudflare API token** (+ account/zone if stored).
2. Resolve zone id for `ven0m0.dpdns.org`:
   `GET https://api.cloudflare.com/client/v4/zones?name=ven0m0.dpdns.org`.
3. Create record:
   `POST /zones/<zone_id>/dns_records` `{type:"TXT", name:"ven0m0.dpdns.org",
   content:"google-site-verification=3Wh2yEDdPRhd4aiVHb_SMccl1Sxh4jCdtodMwyLGOuk",
   ttl:1, proxied:false}`.
4. Verify: `nslookup -type=TXT ven0m0.dpdns.org` returns the value (allow for
   Cloudflare propagation), then user clicks Verify in Search Console.
   (DigitalPlat is only the registrar; no action there.)

## Phase 6 - zram (zstd) + fstab review

**zram** - pick ONE mechanism (currently DietPi's works, zram-tools fails):
- Keep DietPi's native zram (already active, zstd). Remove the redundant, failed
  `zram-tools`: `systemctl disable --now zramswap.service` then `apt-get purge -y zram-tools`.
- Confirm `zstd` is the live algorithm (`cat /sys/block/zram0/comp_algorithm` -> `[zstd]`).
  zram's default zstd level is 3; if an explicit level is wanted it must be set at
  device-setup time via `algorithm_params` (add a small boot hook only if the live
  device isn't already zstd-3). Verify `free -h` still shows swap active afterward.

**fstab** (`/etc/fstab`) - already near-optimal; single safety improvement:
- ext4 root is `noatime,lazytime,commit=120` -> **add `errors=remount-ro`** (fail-safe
  on fs errors). commit=120 is fine (InnoDB has its own durability).
- btrfs is already ideal (`noatime,lazytime,compress=zstd:3,ssd,space_cache=v2,commit=120`).
  Leave as-is; TRIM handled by the enabled `fstrim.timer`. (Optional, not applied
  by default: `discard=async` if we later drop the timer.)
- Validate with `findmnt --verify` / `mount -a` dry check before reboot.

## Phase 7 - Cleanup / removals (LAST, post-verification)

**Disabled NC apps** (authorized set; keep `eurooffice` + `richdocumentscode_arm64`):
`occ app:remove` for `fileviewer` (140M), `suspicious_login` (30M), `circles`
(15M), `office` (7.9M), `files_downloadlimit`, `files_lock`, `related_resources`,
`files_reminders`. (~215M. `user_ldap` kept per user.)

**apt bloat** (authorized): purge the **libreoffice** cluster (self-contained, no
external deps), **pandoc + ripgrep-all** (user OK losing rga), and **unused WiFi
firmware** `firmware-iwlwifi firmware-atheros firmware-mediatek firmware-realtek`
(Pi uses Broadcom). **Keep llvm + mesa.** For each: run `apt-get -s purge ...`
first and confirm the removal list drags nothing needed (nginx/php/mariadb/
brcm firmware), then purge + `apt-get autoremove --purge`.

**Apache uninstall** (folded from old plan): clear DietPi LAMP/LASP markers (IDs
75/76) in the install-state file *before* removing Apache (edit state, do NOT run
their uninstallers - they'd drag out MariaDB/PHP); back up the state file first;
`dietpi-software uninstall 83`; purge leftover `apache2 apache2-*` if any, checking
the autoremove list excludes php/mariadb/nginx libs.

## Phase 8 - Final verification (must pass)

- Office: browser opens/edits a doc; coolwsd runs; `wopi_url` populated.
- files_scripts: 3 image-conversion actions present and working; excludedirs list updated.
- Notes: Keep notes visible in Notes app.
- DNS: TXT resolves; Search Console verifies.
- zram: swap active on zstd, no failed unit (`systemctl --failed` clean).
- fstab: `findmnt --verify` clean; mounts intact after reboot.
- Removals: `dpkg -l | grep -E 'apache2|libreoffice|pandoc|ripgrep-all'` empty of
  `ii`; nginx still serving :80 (`curl -sI localhost`); `occ status` installed:true,
  maintenance off; disabled apps gone; df shows reclaimed space.
- Safety net (snapshot + DB dump + tarball) present under `/mnt/data`.

## Rollback

Files: restore from the read-only btrfs snapshot. DB: `mysql <dbname> < nextcloud-db.sql`.
Configs: extract `configs.tgz`. Apps: `occ app:install <id>`. Apache: `dietpi-software install 83`.
Packages: reinstall from apt. fstab/zram: restore from `configs.tgz`.

## Notes / out of scope

- Single on-device snapshot guards against bad change/deletion, not disk failure
  (off-device backup not requested).
- If ARM64 built-in Collabora proves too heavy for interactive editing, external
  Collabora is the fallback - flagged, not applied without approval.
