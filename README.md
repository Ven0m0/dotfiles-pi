# dotfiles-pi

Bootstrap scripts, dotfiles, and image-build inputs for Raspberry Pi, Debian, and
[DietPi](https://dietpi.com) — the lightweight Debian-based OS this repo targets.

## Showcase

What you get out of the box:

- **A custom DietPi image, built for you.** Push a version tag and GitHub Actions downloads the
  official DietPi base image, layers this repo's packages/dotfiles/scripts onto it with
  [`pimod`](https://github.com/Nature40/pimod), injects your `dietpi.txt` automation config, and
  publishes a ready-to-flash `.img.xz` + checksum as a GitHub Release.
- **A pre-tuned `dietpi.txt`** — AdGuard DNS instead of stock defaults, a trimmed
  `AUTO_SETUP_APT_INSTALLS` package set, and a CI gate that refuses to build until you've replaced
  the placeholder password with a real one, so a real secret can't accidentally ship in an image.
- **`RaspberryPi/Scripts/setup.sh`**, a post-boot setup script covering APT/dpkg performance
  tuning, doc/log cleanup, system hardening, and modern CLI tooling (`fd`, `rg`, `bat`, `eza`,
  `zoxide`, `python3`, `nodejs`, `uv`, `bun`) — plus opt-in one-flag installs for Pi-hole and
  Nextcloud.
- **F2FS conversion helpers** (`RaspberryPi/f2fs-new.sh`, `raspi-f2fs.sh`) for SD card longevity,
  with interactive `fzf`-driven source/destination selection.
- **Repo-aware Claude Code automation** in `.claude/` — hooks that lint every script edit and
  block committing real WiFi credentials, a subagent that knows this repo's specific bash
  conventions, and skills that validate `dietpi.txt` against DietPi's real software catalog before
  you build.

## Getting Started

### Option A — Use a prebuilt image (fastest)

1. Grab the latest release from this repo's GitHub Releases page (built from a tagged `v*` push).
2. Flash it — plain `dd`, Raspberry Pi Imager, or `RaspberryPi/f2fs-new.sh` if you want F2FS.
3. Before first boot, edit `dietpi.txt` on the image's boot partition: at minimum, set your own
   `AUTO_SETUP_GLOBAL_PASSWORD`. Add real WiFi credentials to `dietpi-wifi.txt` there too if needed
   (never commit real credentials to this repo — see below).
4. Boot the Pi. DietPi's first-run automation applies `dietpi.txt` (locale, network, package
   installs, software IDs) unattended.
5. SSH in and run the post-boot setup: `RaspberryPi/Scripts/setup.sh --dry-run` to preview, then
   without the flag to apply. Add `-p`/`-n` if you want Pi-hole and/or Nextcloud too.

### Option B — Build your own image

1. Fork or clone this repo.
2. Edit `dietpi.txt` — password, locale, timezone, network, `AUTO_SETUP_APT_INSTALLS`,
   `AUTO_SETUP_INSTALL_SOFTWARE_ID` — and optionally `dietpi-wifi.txt` (leave its SSID/key fields
   blank if you're committing; a pre-commit hook enforces this).
3. Push a `v*` tag, or trigger `.github/workflows/build-image.yml` manually via
   `workflow_dispatch`. CI will refuse to build if `AUTO_SETUP_GLOBAL_PASSWORD` is still the
   `MUST_SET_PASSWORD_BEFORE_BUILD` placeholder.
4. Download the resulting `.img.xz` and `.sha256` from the new GitHub Release, verify the
   checksum, flash, and boot.
5. Same post-boot step as Option A: run `RaspberryPi/Scripts/setup.sh` once it's up.

See [docs/PLAN.md](docs/PLAN.md) for the image-build architecture and the "Raspberry Pi Scripts"
section below for deeper guides.

## Raspberry Pi Scripts

```text
RaspberryPi/
├── PiClean.sh         # System cleanup script
├── Scripts/
│   ├── apkg.sh            # Interactive APT package helper
│   ├── apply-cmdline.sh   # Apply this repo's tuned kernel cmdline.txt params to any target file
│   ├── blocklist.sh       # hblock wrapper
│   ├── dedupe-media.sh    # Duplicate finder + lossless media optimizer (whiptail/fzf TUI)
│   ├── Kbuild.sh          # Kernel build helper
│   ├── pi-minify.sh       # System minimization helper
│   ├── pi_hole_updater.sh
│   ├── podman-docker.sh
│   ├── setup.sh           # Post-boot Debian/DietPi setup (see Getting Started above)
│   └── sqlite-tune.sh
├── dietpi-chroot.sh   # DietPi image chroot helper (disk image files only, not raw devices)
├── dots/              # Dotfiles and config snippets
├── f2fs-new.sh        # Image-to-F2FS conversion helper
├── raspi-f2fs.sh      # Device flashing helper
└── update.sh          # System update script
```

**One-liners** (fetch-and-run, no clone needed):

```bash
# Update: APT/DietPi/Pi-hole/Pi-Apps upgrades + firmware
curl -fsSL https://raw.githubusercontent.com/Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/update.sh | bash

# Clean: reclaim disk space
curl -fsSL https://raw.githubusercontent.com/Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/PiClean.sh | bash
```

**Post-boot heads-up:** `setup.sh` enables IPv4/IPv6 packet forwarding unconditionally on every
run (turning the Pi into a router/gateway) — this isn't gated behind a flag yet. Revert it if you
don't want that:

```bash
sudo rm -f /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -w net.ipv4.ip_forward=0 net.ipv6.conf.all.forwarding=0 net.ipv6.conf.default.forwarding=0
```

**Recommended post-install checks:**

- Use `dietpi-config` for hostname/locale/timezone options not already covered by `dietpi.txt`.
- Verify SSH key-based access before disabling password auth (`setup.sh -i` opts into insecure
  root/password SSH login — off by default).
- `nala` installs automatically via `dietpi.txt`'s `AUTO_SETUP_APT_INSTALLS` on images built from
  this repo; run `sudo nala fetch` afterward to pick faster mirrors.

**Deeper guides:**

- [docs/QUICKSTART.md](docs/QUICKSTART.md) — F2FS conversion quick start
- [docs/DIETPI_F2FS_GUIDE.md](docs/DIETPI_F2FS_GUIDE.md) — detailed F2FS conversion notes
- [docs/EXAMPLES.md](docs/EXAMPLES.md) — F2FS command patterns and troubleshooting
- [docs/reference/REFERENCES.md](docs/reference/REFERENCES.md) — third-party tools referenced

## Key Components

- **[RaspberryPi/](RaspberryPi/)**: Active Raspberry Pi and DietPi scripts, dotfiles, and build helpers.
  - **[Scripts/setup.sh](RaspberryPi/Scripts/setup.sh)**: Post-boot Debian/DietPi setup — APT/dpkg tuning, doc/log cleanup, hardening, modern CLI tooling (fd, rg, bat, eza, zoxide, python3, nodejs, uv, bun), and opt-in Pi-hole/Nextcloud installs (see `-h` for flags).
- **[docs/](docs/)**: F2FS conversion guides and reference notes (see "Raspberry Pi Scripts" above).
- **[docs/PLAN.md](docs/PLAN.md)**: High-level plan for the custom DietPi image workflow.
- **[Pifile](Pifile)**, **[dietpi.txt](dietpi.txt)**, and **[dietpi-wifi.txt](dietpi-wifi.txt)**: Image customization, first-boot automation, and (optional) WiFi credentials for DietPi builds.
- **[.github/workflows/build-image.yml](.github/workflows/build-image.yml)**: GitHub Actions workflow for building and releasing custom DietPi images.
- **[apps.sh](apps.sh)**: APT/PPA bootstrap helper.
- **[mise.sh](mise.sh)**: `mise` installer.
- **[.claude/](.claude/)**: Repo-aware Claude Code hooks, a bash-focused review subagent, and
  validation skills for this repo's scripts and DietPi config.

## Projects Referenced

- [dietpiconfig](https://github.com/adamdrake/dietpiconfig)
- [DietPi-Dashboard](https://github.com/nonnorm/DietPi-Dashboard)
- [DietPi-Download-Station](https://github.com/lishuren/DietPi-Download-Station)
- [pimod](https://github.com/Nature40/pimod)
- [CustoPiZer](https://github.com/OctoPrint/CustoPiZer)
- [piqemu-action](https://github.com/ethanjli/piqemu-action)
- [pinspawn-action](https://github.com/ethanjli/pinspawn-action)
- [pi-gen-action](https://github.com/usimd/pi-gen-action)
