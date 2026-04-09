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
