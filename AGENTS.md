# AGENTS.md

## Project summary

Personal Raspberry Pi / Debian bootstrap dotfiles and helper scripts.
Bash-first repo with a flat root layout and a `RaspberryPi/` subtree of migrated scripts.
No application framework or package manager manifest exists today.
A GitHub Actions workflow now builds pinned custom DietPi images from this repository.
`docs/PLAN.md` documents the image-build workflow and related follow-up tasks.

## Canonical instruction source

- This file is the canonical agent guidance for the repository.
- `CLAUDE.md` must remain a symlink to `AGENTS.md`, not a separate copy.
- `.github/copilot-instructions.md` must stay aligned with this file — keep it shorter and Copilot-specific.

## Repository layout

```
dotfiles-pi/
├── AGENTS.md              ← canonical agent instructions (this file)
├── CLAUDE.md              ← symlink → AGENTS.md
├── Pifile                 ← pimod build recipe: bakes apps.sh, mise.sh, setup.sh, dots into the DietPi image
├── dietpi.txt              ← DietPi first-boot automation config; injected into images by build-image.yml
├── dietpi-wifi.txt         ← optional WiFi credentials template; injected if present (keep credential fields blank in git)
├── docs/
│   ├── PLAN.md            ← image-build automation plan (future work)
│   └── raspberrypi/
│       ├── README.md / QUICKSTART.md / EXAMPLES.md / DIETPI_F2FS_GUIDE.md
│       └── reference/REFERENCES.md
├── README.md              ← repo overview
├── custom-instructions/   ← shared custom instruction profiles
├── renovate.json          ← Renovate dependency-update config
├── apps.sh                ← apt/PPA bootstrap helper
├── mise.sh                ← installs mise via apt keyring + apt repo
├── .github/
│   ├── copilot-instructions.md
│   └── workflows/
│       └── build-image.yml  ← GitHub Actions DietPi image build/release workflow
├── .claude/
│   └── skills/server-management/SKILL.md  ← generic Claude skill (not repo policy)
└── RaspberryPi/           ← scripts migrated from Ven0m0/Linux-OS
    ├── f2fs-new.sh        ← F2FS conversion for SD card longevity
    ├── raspi-f2fs.sh      ← alternative F2FS helper
    ├── update.sh          ← automated system updates
    ├── PiClean.sh         ← system cleanup
    ├── dietpi-chroot.sh   ← DietPi chroot helper
    ├── Scripts/           ← one-off setup/utility scripts
    │   ├── setup.sh       ← Debian/DietPi setup: APT/dpkg tuning, hardening, modern CLI
    │   │                    tooling, opt-in Pi-hole/Nextcloud (see -h for flags)
    │   ├── podman-docker.sh, apkg.sh, Kbuild.sh, pi-minify.sh, …
    └── dots/              ← dotfiles (.gitconfig, .profile, .inputrc, apt.conf, …)
```

## Image build pipeline

- `Pifile` (via `pimod` in `.github/workflows/build-image.yml`) bakes `apps.sh`, `mise.sh`,
  `RaspberryPi/Scripts/setup.sh`, and `RaspberryPi/dots` into the DietPi image. `apps.sh` and
  `mise.sh` run *during* the image build; `setup.sh` is staged to `/root/setup.sh` but not
  auto-run — it's meant for opt-in, flag-driven use after boot.
- The workflow refuses to build while `dietpi.txt`'s `AUTO_SETUP_GLOBAL_PASSWORD` is still
  `MUST_SET_PASSWORD_BEFORE_BUILD` — this is the one intentional exception to the "no secrets"
  rule below; `dietpi.txt` is a personal automation template the user fills in, not shared code.
- `dietpi-wifi.txt`, if present at repo root, is injected the same way — keep its SSID/key
  fields blank in git; fill them in only on a local, untracked copy.

## Working rules

- Prefer minimal, surgical changes.
- Prefer root-level Bash or documentation edits over refactors.
- Keep scripts explicit, readable, and safe to rerun when practical.
- Use `rg` for file discovery before editing unfamiliar areas.
- Do not introduce dependencies, frameworks, or large structure changes unless explicitly requested.
- `docs/PLAN.md` describes future intent — do not implement planned items unless explicitly asked.

## Bash script conventions

For new or updated shell scripts:

- Use `#!/usr/bin/env bash`.
- Use `set -euo pipefail` for multi-step scripts unless there is a clear reason not to.
- Quote all variable expansions.
- Prefer official apt repositories and keyrings over opaque install pipes.
- Add short comments before commands that make system-wide changes.
- Keep each script focused on one setup task.
- Scripts in `RaspberryPi/` may pre-date these conventions; apply them only when actively editing a script.

## Validation

There is no automated test suite.
Validate changes with the smallest relevant checks:

```bash
# Syntax check root scripts
bash -n apps.sh && bash -n mise.sh
shellcheck apps.sh mise.sh

# Syntax check RaspberryPi scripts when edited
bash -n RaspberryPi/<script>.sh
shellcheck RaspberryPi/<script>.sh
```

If `shellcheck` is not installed, note that and still run the `bash -n` checks.

## Documentation expectations

- Update `README.md` when setup behavior or repository purpose changes.
- Keep `docs/PLAN.md` as a high-level plan; do not expand it with implementation details unless asked.
- Keep long-lived agent instructions centralized in `AGENTS.md`.

## Safety boundaries

Do not:

- add secrets, tokens, or host-specific private values
- hardcode usernames, hostnames, or machine-specific paths
- add destructive commands or remove packages/data without explicit request
- make firewall, SSH, or network-hardening changes without explicit request
- replace safe apt/keyring installation steps with less transparent alternatives
- implement items from `docs/PLAN.md` unless explicitly requested

## Definition of done

A documentation or script change is done when:

1. The edited files match the repository's existing scope and style.
2. Relevant Bash syntax checks pass (`bash -n`).
3. `shellcheck` passes (or its absence is noted).
4. `CLAUDE.md` still resolves as a symlink to `AGENTS.md`.
