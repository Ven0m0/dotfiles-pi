# GitHub Copilot Instructions

Read `/home/runner/work/dotfiles-pi/dotfiles-pi/AGENTS.md` first for the full repository guidance.
`CLAUDE.md` should remain a symlink to `AGENTS.md`.

## Repo context

- Small Raspberry Pi / Debian dotfiles and bootstrap repository
- Main working files are root-level Bash scripts plus lightweight docs
- No package manifest, CI workflow, or automated test suite currently exists

## How to work in this repo

- Prefer small Bash or Markdown edits.
- Keep scripts explicit, readable, and safe to rerun when practical.
- Use `rg` for discovery before editing unfamiliar files.
- Avoid broad refactors or new tooling unless explicitly requested.

## Bash expectations

- Prefer `#!/usr/bin/env bash` for new scripts.
- Prefer `set -euo pipefail` for multi-step scripts.
- Quote variable expansions.
- Favor official apt repositories and keyrings over opaque install commands.
- Add brief comments before commands with machine-wide effects.

## Validation

Run the smallest relevant checks for script changes:

```bash
bash -n /home/runner/work/dotfiles-pi/dotfiles-pi/apps.sh
bash -n /home/runner/work/dotfiles-pi/dotfiles-pi/mise.sh
shellcheck /home/runner/work/dotfiles-pi/dotfiles-pi/apps.sh /home/runner/work/dotfiles-pi/dotfiles-pi/mise.sh
```

If `shellcheck` is unavailable, mention that and still run the syntax checks.

## Documentation guidance

- Update `README.md` when setup behavior changes.
- Keep `TODO.md` for future work and references.
- Keep repository-wide agent guidance in `AGENTS.md`, not duplicated here.

## Avoid

- secrets or machine-specific values
- destructive system changes without explicit request
- unrelated cleanup or restructuring
