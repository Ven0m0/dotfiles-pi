# GitHub Copilot Instructions

`AGENTS.md` is the canonical agent guidance — read it for the full picture.
`CLAUDE.md` must remain a symlink to `AGENTS.md`.

## Repo at a glance

- Raspberry Pi / Debian bootstrap dotfiles and helper scripts
- Root-level: `apps.sh` (apt/PPA), `mise.sh` (mise tool manager), `PLAN.md` (future image-build automation)
- `RaspberryPi/`: migrated scripts — F2FS helpers, update/cleanup scripts, dotfiles, reference docs
- No CI, no test suite, no package manifest today

## How to work here

- Prefer small, targeted Bash or Markdown edits.
- Use `rg` for discovery before editing unfamiliar files.
- Keep scripts explicit, readable, and safe to rerun.
- Do not implement items from `PLAN.md` unless explicitly asked.
- Avoid broad refactors or new tooling unless explicitly requested.

## Bash expectations

- `#!/usr/bin/env bash` shebang.
- `set -euo pipefail` for multi-step scripts.
- Quote all variable expansions.
- Prefer official apt keyrings over opaque install pipes.
- Add brief comments before commands with system-wide effects.

## Validation

```bash
bash -n apps.sh && bash -n mise.sh
shellcheck apps.sh mise.sh
# Also check any RaspberryPi/*.sh files you touch (e.g., bash -n RaspberryPi/f2fs-new.sh)
```

Note if `shellcheck` is unavailable; still run `bash -n`.

## Safety — never do this without explicit request

- Hardcode usernames, hostnames, or machine-specific paths
- Add secrets or tokens
- Add destructive commands or remove packages/data
- Change firewall, SSH, or network settings
- Use opaque install pipes instead of apt keyrings
