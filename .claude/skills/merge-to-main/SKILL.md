---
name: merge-to-main
description: Use when the user wants to commit staged/local changes, sync with the remote (and an upstream fork source if one is configured), and push — without losing local work. Triggers on "merge my changes", "push to remote", "commit and push", "merge into main", "sync local changes", "get my changes onto main", "sync with upstream", "pull upstream changes", "pull remote changes while keeping mine", or any request to integrate local/staged/branch work with a moved-on remote and push it. Detects the repo's actual remote topology instead of assuming one — works the same way in any git project.
---

# Merge to Main

Full sync: bring in remote/upstream changes, keep local work, commit, push. Repo-agnostic —
every step below discovers facts about the repo (remotes, default branch, hook stack) instead
of assuming them.

## Step 1: Assess state

```bash
git status
git remote -v
git branch -a
git log --oneline -5
```

Note: current branch, staged vs. unstaged vs. untracked changes, and which remotes exist.

## Step 2: Determine remote topology

```bash
git remote -v
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || git remote show origin | grep 'HEAD branch'
```

Two shapes, handle whichever applies:

- **Single remote (`origin` only)** — the common case. Local main tracks origin directly; skip
  straight to Step 5 using `origin` as the only remote.
- **Fork setup (`origin` + `upstream`)** — `origin` is the user's own fork/repo, `upstream` is
  the source it was forked from. Sync from `upstream` first, then `origin`, and push only to
  `origin` — never to `upstream` unless the user explicitly asks for a PR against it.

If the user mentions an upstream repo URL by name and no `upstream` remote exists yet, add it:

```bash
git remote add upstream <url-the-user-gave>
```

Don't invent an upstream URL — only add one the user actually specified.

## Step 3: Branch staged/local changes off main (only if needed)

Most of the time, skip this — `git pull --rebase --autostash` (Step 5) safely carries local
uncommitted changes through a sync without a separate branch. Only create a feature branch when:

- the project's workflow expects PRs rather than direct pushes to main, or
- local changes are substantial enough that isolating them before a risky upstream merge is
  safer (e.g. the fork-topology case with a history that may have diverged).

```bash
git checkout -b feature/<short-description>
```

Name the branch from the content (3–5 words, kebab-case). If unsure whether the project wants
this, ask rather than assuming — check for a CONTRIBUTING doc or recent PR-based commit history
first (`git log --merges -5`).

## Step 4: Commit local changes

```bash
git add <files>   # prefer explicit paths over -A; never stage secrets/credentials
git commit -m "$(cat <<'EOF'
<short imperative summary under 72 chars>

- <group of related changes>
- <group of related changes>
EOF
)"
```

Do NOT use `--no-verify`. If a pre-commit/pre-push hook fails, fix the root cause and re-stage:

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Lint/format hook fails | Project has a linter/formatter (ruff, eslint, biome, shellcheck, gofmt, etc.) | Run that project's actual lint/format command — check `package.json` scripts, `Makefile`, or `.pre-commit-config.yaml` for the exact invocation — then re-stage the fixed files |
| "no files processed" / hook skipped everything | Staged file type is in the tool's ignore list | Check the hook's config (e.g. `.pre-commit-config.yaml`, tool-specific ignore file) for an overly broad exclude pattern |
| Executable-bit / shebang check fails | Script has a shebang but isn't `chmod +x` | `git add --chmod=+x <file>` |
| Secret-scanning hook fails | A staged file looks like it contains a credential | Do not bypass — remove the secret from the file before continuing |

After each fix, re-stage the affected files and retry the commit.

## Step 5: Sync with remote(s)

**Single-remote case:**

```bash
git pull --rebase --autostash origin <default-branch>
```

`--autostash` stashes any uncommitted work, applies the pull, then re-applies the stash — so
local changes survive the sync without a manual dance. If the autostash re-apply reports a
conflict, run `git stash list` / `git stash pop` and resolve by hand.

**Fork-with-upstream case:**

```bash
git checkout <default-branch>
git fetch upstream
git pull --autostash upstream <default-branch>
```

Then also pick up anything pushed directly to the fork since the last sync:

```bash
git pull -r --autostash origin <default-branch>
```

### Conflict resolution strategy (fork case)

There's no universal rule — decide per file type, and ask the user if a file's provenance is
unclear:

| File looks like... | Default |
|---------------------|---------|
| Auto-generated / CI-produced data (build artifacts, generated JSON/locks, scraped data dumps) | Accept upstream (`git checkout --theirs`) — it's regenerated anyway |
| Hand-written source code the user is actively working on | Keep local (`git checkout --ours`) or merge manually |
| Docs / config touched on both sides | Merge manually, preferring whichever edit is more recent or more complete |

After resolving: `git add <resolved-files> && git rebase --continue` (or `git merge --continue`
if a merge rather than rebase is in progress — check with `git status`).

If a feature branch was created in Step 3, merge it back now, preferring fast-forward:

```bash
git merge --ff-only feature/<branch-name>   # falls back to `git merge feature/<branch-name>` if histories diverged
```

## Step 6: Push

```bash
git push origin <default-branch>
```

Before pushing, confirm `origin` is actually the repo the user intends to push to
(`git remote -v`) — especially in the fork case, where pushing to `upstream` instead of `origin`
would open unwanted changes against a repo the user doesn't own. If a feature branch was used:

```bash
git branch -d feature/<branch-name>
git push origin --delete feature/<branch-name>
```

## Step 7: Commit any remaining workflow-only changes

Files modified by the workflow itself but not part of the original change set (e.g. config
files updated to fix a hook failure) won't be on a feature branch used above. Commit them
directly to the default branch and push:

```bash
git add <files>
git commit -m "<short message>"
git push origin <default-branch>
```
