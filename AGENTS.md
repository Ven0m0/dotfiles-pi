# AGENTS.md

## Project summary

Personal Raspberry Pi / Debian bootstrap dotfiles and helper scripts.
Bash-first repo with a flat root layout and a `RaspberryPi/` subtree of migrated scripts.
No application framework, package manager manifest, or automated CI workflow exists today.
`PLAN.md` describes the intended automated image-build workflow using GitHub Actions.

## Canonical instruction source

- This file is the canonical agent guidance for the repository.
- `CLAUDE.md` must remain a symlink to `AGENTS.md`, not a separate copy.
- `.github/copilot-instructions.md` must stay aligned with this file — keep it shorter and Copilot-specific.

## Repository layout

```
dotfiles-pi/
├── AGENTS.md              ← canonical agent instructions (this file)
├── CLAUDE.md              ← symlink → AGENTS.md
├── PLAN.md                ← image-build automation plan (future work)
├── README.md              ← repo overview
├── TODO.md                ← future work and migration notes
├── renovate.json          ← Renovate dependency-update config
├── apps.sh                ← apt/PPA bootstrap helper
├── mise.sh                ← installs mise via apt keyring + apt repo
├── .github/
│   └── copilot-instructions.md
├── .claude/
│   └── skills/server-management/SKILL.md  ← generic Claude skill (not repo policy)
└── RaspberryPi/           ← scripts migrated from Ven0m0/Linux-OS
    ├── README.md / QUICKSTART.md / EXAMPLES.md / DIETPI_F2FS_GUIDE.md
    ├── f2fs-new.sh        ← F2FS conversion for SD card longevity
    ├── raspi-f2fs.sh      ← alternative F2FS helper
    ├── update.sh          ← automated system updates
    ├── PiClean.sh         ← system cleanup
    ├── dietpi-chroot.sh   ← DietPi chroot helper
    ├── Scripts/           ← one-off setup/utility scripts
    │   ├── setup.sh       ← initial system hardening
    │   ├── podman-docker.sh, apkg.sh, Kbuild.sh, pi-minify.sh, …
    ├── dots/              ← dotfiles (.gitconfig, .profile, .inputrc, apt.conf, …)
    └── docs/              ← reference notes (dietpi.txt, pihole.txt, Kernel.txt, …)
```

## Working rules

- Prefer minimal, surgical changes.
- Prefer root-level Bash or documentation edits over refactors.
- Keep scripts explicit, readable, and safe to rerun when practical.
- Use `rg` for file discovery before editing unfamiliar areas.
- Do not introduce dependencies, frameworks, or large structure changes unless explicitly requested.
- `PLAN.md` describes future intent — do not implement planned items unless explicitly asked.

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
bash -n apps.sh
bash -n mise.sh
shellcheck apps.sh mise.sh

# Syntax check RaspberryPi scripts when edited
bash -n RaspberryPi/<script>.sh
shellcheck RaspberryPi/<script>.sh
```

If `shellcheck` is not installed, note that and still run the `bash -n` checks.

## Documentation expectations

- Update `README.md` when setup behavior or repository purpose changes.
- Keep `TODO.md` focused on future work, references, and migration notes.
- Keep `PLAN.md` as a high-level plan; do not expand it with implementation details unless asked.
- Keep long-lived agent instructions centralized in `AGENTS.md`.

## Safety boundaries

Do not:

- add secrets, tokens, or host-specific private values
- hardcode usernames, hostnames, or machine-specific paths
- add destructive commands or remove packages/data without explicit request
- make firewall, SSH, or network-hardening changes without explicit request
- replace safe apt/keyring installation steps with less transparent alternatives
- implement items from `PLAN.md` unless explicitly requested

## Definition of done

A documentation or script change is done when:

1. The edited files match the repository's existing scope and style.
2. Relevant Bash syntax checks pass (`bash -n`).
3. `shellcheck` passes (or its absence is noted).
4. `CLAUDE.md` still resolves as a symlink to `AGENTS.md`.
