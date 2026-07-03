---
name: validate-repo-script
description: Run this repo's (dotfiles-pi) Bash validation recipe from AGENTS.md — bash -n plus shellcheck — against one script, a list of scripts, or every tracked *.sh file. Use when asked to "validate", "check", or "lint" scripts in this repo, before claiming a script change is done, or before a commit that touches .sh files. A PostToolUse hook already runs this per-edit; use this skill for a full/batch pass instead.
allowed-tools: Read, Bash, Glob
---

# Validate Repo Script

Implements `AGENTS.md`'s "Validation" and "Definition of done" sections exactly — this skill
exists so that recipe doesn't have to be re-derived from `AGENTS.md` by hand each time.

## Steps

1. **Determine scope.**
   - If the user named specific file(s), use those.
   - Otherwise, discover all tracked shell scripts: root-level (`apps.sh`, `mise.sh`) plus every
     `.sh` under `RaspberryPi/` (`git ls-files '*.sh'` is the reliable way to do this — it
     respects what's actually tracked, not stray untracked scratch files).

2. **For each script, run in order and capture output:**
   ```bash
   bash -n <file>
   shellcheck <file>
   ```
   If `shellcheck` is not installed, note that explicitly per `AGENTS.md` ("If shellcheck is not
   installed, note that and still run the bash -n checks") — do not silently skip it or treat its
   absence as a pass.

3. **Classify shellcheck output by severity**, not just pass/fail:
   - Any `(error)` finding → the script fails validation.
   - `(warning)` findings → flag them, but they don't block; note if they look like a real bug
     (e.g. `SC2034` on a variable that's actually used via `sudo VAR=val cmd` elsewhere, or
     `SC2154`) versus genuinely cosmetic.
   - `(info)`/`(style)` findings → summarize the count, don't enumerate each one unless asked.

4. **Report per-script**: pass/fail, and if failed, the specific `bash -n` syntax error or
   shellcheck `(error)`-level finding with file:line. Don't just say "shellcheck failed" — quote
   the actual finding.

5. **Roll up a summary line** at the end: `N/M scripts pass (bash -n clean, no shellcheck errors)`.

## Notes specific to this repo

- `RaspberryPi/` scripts "may pre-date these conventions" per `AGENTS.md` — a pre-existing
  warning in an untouched script is not a regression. Only treat NEW findings (in a script you
  just edited this session) as things to fix before calling the work done.
- This validates syntax and static-analysis correctness only. It does not catch logic bugs like
  a `--dry-run` flag that doesn't actually gate side effects — for that class of review, use the
  `bash-reviewer` subagent instead.
