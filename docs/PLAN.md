# DietPi Custom Image Build Plan

## Overview

This document describes the high-level plan for building custom DietPi OS images for Raspberry Pi using
a GitHub Actions–based automated pipeline. The goal is to produce reproducible, pre-configured images
that bake in the dotfiles, packages, and system tuning from this repository so a freshly flashed card
boots straight into a ready-to-use environment.

---

## Reference Projects

The following projects inform the tooling choices and workflow design:

| Project | Role in this plan |
|---|---|
| [MichaIng/DietPi](https://github.com/MichaIng/DietPi) | Official DietPi build scripts and `dietpi.txt` automation config — canonical reference for DietPi-specific customisation hooks |
| [RPi-Distro/pi-gen](https://github.com/RPi-Distro/pi-gen) | Stage-based Raspberry Pi OS image builder; the `pi-gen-action` GitHub Action wraps it for CI use |
| [tolstoyevsky/pieman](https://github.com/tolstoyevsky/pieman) | Python-based, YAML-configured image builder; useful reference for cross-compilation patterns |
| [Nature40/pimod](https://github.com/Nature40/pimod) | Pifile (Dockerfile-style) image modifier; runs inside QEMU — **primary customisation driver** for this repo |
| [jmcerrejon/PiKISS](https://github.com/jmcerrejon/PiKISS) | Curated script library for Pi software installs; good reference for per-package install recipes |
| [heeplr/rpi-cookstrap](https://github.com/heeplr/rpi-cookstrap) | Modular bash-plugin bootstrap system; reference for composable pre-first-boot setup patterns |
| [gitbls/sdm](https://github.com/gitbls/sdm) | System Definition Manager — plugin-based image customiser with first-boot service; reference for pre-seeding and phase-separation patterns |

---

## Architecture

```
Official DietPi base image (downloaded from https://dietpi.com)
        │
        ▼
  pimod (Pifile)          ← image-level customisation: packages, dotfiles, F2FS prep
        │
        ▼
  dietpi.txt injection    ← unattended first-boot config (locale, hostname, software IDs)
        │
        ▼
  GitHub Actions release  ← compressed .img artifact uploaded to GitHub Releases
```

**Why pimod over pi-gen for DietPi images?**
`pi-gen` builds Raspberry Pi OS from scratch and carries the wrong base; building on top of an
official DietPi `.img` with `pimod` is simpler and stays in sync with upstream DietPi releases
automatically.

---

## Build Phases

### Phase 1 — Base Image Acquisition

- Download the latest official DietPi ARMv8 image (or ARM64/x86 as needed) from `https://dietpi.com`.
- Verify the image SHA256 checksum before proceeding.
- Cache the download in the GitHub Actions workspace to avoid re-downloading on re-runs.

### Phase 2 — Pifile Customisation (`pimod`)

Write a `Pifile` that layers the following onto the DietPi base:

1. **System packages** — run `apps.sh` logic inside the chroot (apt/PPA installs).
2. **mise tool manager** — run `mise.sh` logic to install and configure `mise`.
3. **Dotfiles** — copy `RaspberryPi/dots/` entries into the default user home and `/etc/skel`.
4. **F2FS prep** — install `f2fs-tools` and embed the conversion helper so first-boot can opt in.
5. **Hardening** — apply `RaspberryPi/Scripts/setup.sh` hardening steps non-interactively.

### Phase 3 — DietPi Automation Config

Inject a `dietpi.txt` (and optionally `dietpi-wifi.txt`) into the boot partition to pre-seed:

- Locale, timezone, hostname, keyboard layout.
- Auto-install software IDs (from `dietpi-software`) matching the curated package list.
- Disable first-run survey and enable auto-login where appropriate.

### Phase 4 — Image Packaging

- Shrink the image with `pishrink.sh` (or equivalent) to minimise artifact size.
- Compress to `.img.xz`.
- Generate a SHA256 checksum file alongside the artifact.

### Phase 5 — GitHub Actions Release

- Trigger on a new git tag (`v*`) or manually via `workflow_dispatch`.
- Upload the compressed image and checksum to a GitHub Release.
- Optionally run a smoke-test in QEMU (`piqemu-action` / `pinspawn-action`) before publishing.

---

## GitHub Actions Workflow (high-level)

```
on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - checkout
      - download + verify DietPi base image
      - run pimod with Pifile
      - inject dietpi.txt
      - shrink + compress image
      - upload artifact / create release
  test (optional):
    needs: build
    steps:
      - boot image in QEMU via piqemu-action
      - assert key services are running
```

---

## Customisation Layers Summary

| Layer | Source in this repo | Mechanism |
|---|---|---|
| APT packages & PPAs | `apps.sh` | Sourced inside Pifile `RUN` step |
| mise + dev tools | `mise.sh` | Sourced inside Pifile `RUN` step |
| Shell dotfiles | `RaspberryPi/dots/` | Copied via Pifile `COPY` step |
| F2FS tooling | `RaspberryPi/f2fs-new.sh` | `f2fs-tools` installed; script embedded |
| System hardening | `RaspberryPi/Scripts/setup.sh` | Run non-interactively inside Pifile |
| DietPi first-boot | `dietpi.txt` template (to be created) | Written to `/boot` partition |

---

## Open Items

- [ ] Create `Pifile` at repo root (or `build/Pifile`).
- [ ] Create `dietpi.txt` template with sensible defaults and inline comments.
- [ ] Create `.github/workflows/build-image.yml` GitHub Actions workflow.
- [ ] Decide on target board(s): RPi 4, RPi 5, RPi Zero 2 W, or all three.
- [ ] Decide whether to publish releases publicly or keep artifacts private.
- [ ] Evaluate QEMU smoke-test feasibility (`piqemu-action`) for CI gating.
- [ ] Pin DietPi base image version (or always track `latest` stable).

---

## Existing Script Improvement Tasks

The tasks below track improvements to the existing helper scripts in this repository.

## Task Index

| #  | ID   | Title                                                       | Sev    | Cat      | Size | Blocks       |
|----|------|-------------------------------------------------------------|--------|----------|------|--------------|
| 1  | T001 | Fix stale Linux-OS URLs in docs/raspberrypi/README.md       | high   | docs     | S    | —            |
| 2  | T002 | Fix stale Linux-OS project URL in DIETPI_F2FS_GUIDE.md      | medium | docs     | S    | —            |
| 3  | T003 | Complete "Settings todo" stub in docs/raspberrypi/README.md | medium | docs     | S    | —            |
| 4  | T004 | Install fsck.f2fs in rootfs when missing in f2fs-new.sh     | high   | bug      | M    | —            |
| 5  | T005 | Add reboot confirmation prompt to Kbuild.sh                 | medium | refactor | S    | —            |

---

## Tasks

### T001 · Fix stale Linux-OS URLs in docs/raspberrypi/README.md

**File:** `docs/raspberrypi/README.md:34` and `docs/raspberrypi/README.md:40`
**Severity:** high · **Category:** docs · **Size:** S
**Blocks:** — · **Blocked by:** —

**Context:**
```
### Quick Start Scripts

curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/update.sh | bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/PiClean.sh | bash
```

**Intent:** After the migration from `Ven0m0/Linux-OS` to `Ven0m0/dotfiles-pi`, the Quick Start curl commands in the README were not updated to point at the new canonical repo.

**Acceptance criteria:**
- [ ] Line 34: URL base changed from `Ven0m0/Linux-OS/refs/heads/main` to `Ven0m0/dotfiles-pi/refs/heads/main`.
- [ ] Line 40: URL base changed from `Ven0m0/Linux-OS/refs/heads/main` to `Ven0m0/dotfiles-pi/refs/heads/main`.
- [ ] Both resulting URLs follow the pattern `https://raw.githubusercontent.com/Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/<script>.sh`.
- [ ] No other lines in `docs/raspberrypi/README.md` are modified.

**Implementation:**
```
sed -i 's|Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/update.sh|Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/update.sh|' docs/raspberrypi/README.md
sed -i 's|Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/PiClean.sh|Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/PiClean.sh|' docs/raspberrypi/README.md
```

---

### T002 · Fix stale Linux-OS project URL in DIETPI_F2FS_GUIDE.md

**File:** `docs/raspberrypi/DIETPI_F2FS_GUIDE.md:224`
**Severity:** medium · **Category:** docs · **Size:** S
**Blocks:** — · **Blocked by:** —

**Context:**
```
- Project repo: https://github.com/Ven0m0/Linux-OS
```

**Intent:** The F2FS guide retains a footer pointing at the old source repository; readers following the link land at a different repo from where the scripts actually live.

**Acceptance criteria:**
- [ ] Line 224 URL updated to `https://github.com/Ven0m0/dotfiles-pi`.
- [ ] No other content on that line changes.
- [ ] Surrounding lines in the file are not modified.

**Implementation:**
```
sed -i 's|https://github.com/Ven0m0/Linux-OS|https://github.com/Ven0m0/dotfiles-pi|' docs/raspberrypi/DIETPI_F2FS_GUIDE.md
```

---

### T003 · Complete "Settings todo" stub in docs/raspberrypi/README.md

**File:** `docs/raspberrypi/README.md:43–47`
**Severity:** medium · **Category:** docs · **Size:** S
**Blocks:** — · **Blocked by:** —

**Context:**
```markdown
### Settings todo

```markdown
net.ipv4.ip_forward=1
https://gitlab.com/volian/nala/-/blob/main/docs/nala-fetch.8.rst?ref_type=heads
```
```

**Intent:** The author left a raw placeholder noting two post-install settings to document: enabling IPv4 forwarding (required for routing/VPN use cases) and configuring `nala` as an apt front-end. The section has no prose, no commands, and an incorrect fenced-code language tag (`markdown` instead of `bash` or `ini`).

**Acceptance criteria:**
- [ ] Section heading renamed from `### Settings todo` to `### Recommended post-install settings` (or equivalent imperative heading).
- [ ] `net.ipv4.ip_forward=1` presented as a sysctl command (`sudo sysctl -w net.ipv4.ip_forward=1`) or as a `/etc/sysctl.d/` snippet with a brief explanation.
- [ ] `nala` fetch link replaced by a one-liner install command plus a pointer to the nala-fetch man page URL.
- [ ] Code blocks use the correct language tag (`bash` or `ini`).
- [ ] No other sections in the file are modified.

**Implementation:**
Replace lines 43–49 with:
```markdown
### Recommended post-install settings

Enable IPv4 forwarding (required for VPN/routing):
```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

Use [nala](https://gitlab.com/volian/nala) as a friendlier apt front-end:
```bash
sudo apt install nala
sudo nala fetch   # choose fastest mirrors
```
```

---

### T004 · Install fsck.f2fs in rootfs when missing in f2fs-new.sh

**File:** `RaspberryPi/f2fs-new.sh:433–436`
**Severity:** high · **Category:** bug · **Size:** M
**Blocks:** — · **Blocked by:** —

**Context:**
```bash
# Basic warning: fsck.f2fs may not exist; not fatal for boot
if [[ ! -x "$DST_MNT_ROOT/sbin/fsck.f2fs" && ! -x "$DST_MNT_ROOT/usr/sbin/fsck.f2fs" ]]; then
  log "WARN: fsck.f2fs not found in rootfs. Boot should still work; fsck service (if any) may complain.\n"
fi
```

**Intent:** The script converts a root filesystem to F2FS but does not ensure `f2fs-tools` (which provides `fsck.f2fs`) is installed inside the new rootfs. On first boot the systemd `systemd-fsck@.service` unit will fail if `fsck.f2fs` is absent, producing boot-time errors and potentially triggering emergency mode on strict configurations.

**Acceptance criteria:**
- [ ] When `fsck.f2fs` is absent, the script attempts to install `f2fs-tools` into the rootfs via `chroot "$DST_MNT_ROOT" apt-get install -y f2fs-tools` (requires network or local cache to be available during conversion).
- [ ] If the chroot install fails (non-zero exit), the existing WARN message is still emitted and execution continues (non-fatal path preserved).
- [ ] A comment above the block explains why `f2fs-tools` is needed at first boot.
- [ ] `bash -n RaspberryPi/f2fs-new.sh` and `shellcheck RaspberryPi/f2fs-new.sh` pass after the change.
- [ ] The fallback WARN log line is preserved so users are informed when automatic install also fails.

**Implementation:**
Replace the existing `if` block at lines 433–436 with:
```bash
# f2fs-tools provides fsck.f2fs; required by systemd-fsck@.service on first boot
if [[ ! -x "$DST_MNT_ROOT/sbin/fsck.f2fs" && ! -x "$DST_MNT_ROOT/usr/sbin/fsck.f2fs" ]]; then
  log "fsck.f2fs not found — attempting to install f2fs-tools into rootfs …\n"
  if ! chroot "$DST_MNT_ROOT" apt-get install -y --no-install-recommends f2fs-tools 2>/dev/null; then
    log "WARN: f2fs-tools install failed. Boot should still work; fsck service (if any) may complain.\n"
  fi
fi
```

---

### T005 · Add reboot confirmation prompt to Kbuild.sh

**File:** `RaspberryPi/Scripts/Kbuild.sh:7` and surrounding install section
**Severity:** medium · **Category:** refactor · **Size:** S
**Blocks:** — · **Blocked by:** —

**Context:**
```bash
# WARNING: This script will reboot the system after kernel installation
```
(also repeated in the `usage()` heredoc at line 46)

**Intent:** The author documented the reboot side-effect in a comment and in `--help` output, but the script does not ask for confirmation before rebooting. A user who runs the script unaware or on a remote machine will lose their session without warning.

**Acceptance criteria:**
- [ ] Before executing `reboot` (or `systemctl reboot`), the script prints the warning and prompts `Reboot now? [y/N]:`.
- [ ] If the user answers anything other than `y` or `Y`, the script prints `Reboot skipped. Reboot manually to load the new kernel.` and exits 0.
- [ ] The prompt is bypassed when a `-y` / `--yes` flag is passed (or when `stdin` is not a TTY, i.e., `[[ ! -t 0 ]]`), so non-interactive callers are not broken.
- [ ] `bash -n RaspberryPi/Scripts/Kbuild.sh` and `shellcheck RaspberryPi/Scripts/Kbuild.sh` pass after the change.
- [ ] The existing `WARNING` comment at line 7 and in `usage()` is kept.

**Implementation:**
Locate the `reboot` call in `Kbuild.sh`. Replace it with:
```bash
_confirm_reboot() {
  if [[ ${AUTO_YES:-0} -eq 1 || ! -t 0 ]]; then
    return 0
  fi
  read -r -p "$(warn 'Reboot now to load the new kernel? [y/N]: ')" _ans
  [[ ${_ans,,} == y ]] || { log "Reboot skipped. Run: sudo reboot"; exit 0; }
}
_confirm_reboot
sudo reboot
```
Add `AUTO_YES=0` near the top of the script and set it to `1` when `-y`/`--yes` is parsed in the argument loop.
