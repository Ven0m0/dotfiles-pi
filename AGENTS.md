# AGENTS.md

## Project summary

This repository contains Raspberry Pi / Debian bootstrap dotfiles and helper scripts.
It is a very small Bash-first repo with a flat root layout and no application framework, package manager manifest, or automated CI workflow.

## Canonical instruction source

- Treat this file as the canonical agent guidance for the repository.
- Keep `CLAUDE.md` as a symlink to `AGENTS.md`, not a separate copy.
- Keep `.github/copilot-instructions.md` aligned with this file, but shorter and Copilot-specific.

## Repository layout

- `README.md` — short description of the repo
- `TODO.md` — future ideas and migration notes
- `apps.sh` — apt/PPA bootstrap helper
- `mise.sh` — installs `mise` using an apt keyring and apt repository
- `.claude/skills/server-management/SKILL.md` — generic Claude skill; useful context, but not repository policy

## Working rules

- Prefer minimal, surgical changes.
- Prefer root-level Bash or documentation edits over refactors.
- Keep scripts explicit, readable, and safe to rerun when practical.
- Use `rg` for file discovery before editing unfamiliar areas.
- Do not introduce dependencies, frameworks, or large structure changes unless explicitly requested.

## Bash script conventions

For new or updated shell scripts:

- Use `#!/usr/bin/env bash`.
- Prefer `set -euo pipefail` for multi-step scripts unless there is a clear reason not to.
- Quote variable expansions.
- Prefer official apt repositories and keyrings over opaque install pipes.
- Add short comments before commands that make system-wide changes.
- Keep each script focused on one setup task.

## Validation

There is no automated test suite in this repository today.
Validate changes with the smallest relevant checks:

```bash
bash -n /home/runner/work/dotfiles-pi/dotfiles-pi/apps.sh
bash -n /home/runner/work/dotfiles-pi/dotfiles-pi/mise.sh
shellcheck /home/runner/work/dotfiles-pi/dotfiles-pi/apps.sh /home/runner/work/dotfiles-pi/dotfiles-pi/mise.sh
```

If `shellcheck` is not installed, note that and still run the `bash -n` checks.

## Documentation expectations

- Update `README.md` when setup behavior or repository purpose changes.
- Keep `TODO.md` focused on future work, references, and migration notes.
- Keep long-lived agent instructions centralized in `AGENTS.md`.

## Safety boundaries

Do not:

- add secrets, tokens, or host-specific private values
- hardcode usernames, hostnames, or machine-specific paths
- add destructive commands or remove packages/data without explicit request
- make firewall, SSH, or network-hardening changes without explicit request
- replace safe apt/keyring installation steps with less transparent alternatives

## Definition of done

A documentation or script change is done when:

1. The edited files match the repository's existing scope and style.
2. Relevant Bash syntax checks pass.
3. `shellcheck` passes when available.
4. `CLAUDE.md` still resolves to `AGENTS.md`.
