---
task: "plan-implementation"
phase: "explore"
status: "complete"
timestamp: "2026-04-09T20:55:00Z"
agent: "explorer"
model: "GPT-5.4"
---

## Codebase Map

```
dotfiles-pi/
├── .github/workflows/       [MISSING - needs creation]
├── RaspberryPi/
│   ├── README.md            [T001 targets lines 34, 40]
│   ├── DIETPI_F2FS_GUIDE.md [T002 targets line 223]
│   ├── f2fs-new.sh          [T004 ALREADY FIXED - see findings]
│   ├── Scripts/
│   │   └── Kbuild.sh        [T005 ALREADY FIXED - see findings]
│   ├── dots/                [dotfiles for image baking]
│   └── docs/
│       └── dietpi.txt       [template exists, needs repo root copy]
├── PLAN.md                  [master implementation plan]
├── apps.sh                  [APT/PPA bootstrap - 3 lines only]
├── mise.sh                  [mise installer - 8 lines]
├── Pifile                   [MISSING - needs creation]
└── build-image.yml          [MISSING - needs creation in .github/workflows/]
```

## Relevant Files

### Direct Task Targets (T001-T005)

| File | Task | Status | Lines |
|------|------|--------|-------|
| `RaspberryPi/README.md` | T001 | **ALREADY FIXED** ✓ | 34, 40 correct URLs |
| `RaspberryPi/README.md` | T003 | **ALREADY COMPLETED** ✓ | Lines 43-49 match spec |
| `RaspberryPi/DIETPI_F2FS_GUIDE.md` | T002 | **ALREADY FIXED** ✓ | Line 223 correct URL |
| `RaspberryPi/f2fs-new.sh` | T004 | **ALREADY FIXED** ✓ | Lines 433-439 match spec |
| `RaspberryPi/Scripts/Kbuild.sh` | T005 | **ALREADY FIXED** ✓ | Lines 129-139 match spec |

### Open Items (from PLAN.md)

| Item | File Path | Priority | Blocker |
|------|-----------|----------|---------|
| Create Pifile | `Pifile` (repo root) | HIGH | Blocks image build |
| Create workflow | `.github/workflows/build-image.yml` | HIGH | Blocks automation |
| dietpi.txt template | Copy `RaspberryPi/docs/dietpi.txt` to root | MEDIUM | Template exists |
| Target board decision | N/A (policy decision) | LOW | User input needed |
| Release visibility | N/A (policy decision) | LOW | User input needed |
| QEMU smoke test | Workflow integration | LOW | Optional feature |
| Version pinning | Workflow config | LOW | Optional feature |

## Patterns Found

### Script Conventions
- **Shebang**: `#!/usr/bin/env bash` or `#!/bin/bash`
- **Error handling**: Most scripts use `set -euo pipefail`
- **Shellcheck**: Kbuild.sh has `# shellcheck enable=all shell=bash`
- **Color output**: Helper functions (`log`, `warn`, `err`) with ANSI codes
- **Confirmation prompts**: `AUTO_YES` flag pattern for non-interactive mode

### Repository Structure
- **Migration complete**: All references updated from `Ven0m0/Linux-OS` to `Ven0m0/dotfiles-pi`
- **Dotfiles location**: `RaspberryPi/dots/` for image baking
- **Documentation**: Multiple guides (README, QUICKSTART, DIETPI_F2FS_GUIDE)
- **No build directory**: All artifacts will be workspace-level (GitHub Actions)

### Existing Assets
- **apps.sh**: Minimal (3 lines) - only adds PPA, no actual package list
- **mise.sh**: Complete installer for mise tool manager
- **dietpi.txt**: Full template exists at `RaspberryPi/docs/dietpi.txt` with defaults
- **f2fs tooling**: Both `f2fs-new.sh` (production) and `raspi-f2fs.sh` (variant)

## Risks

### Implementation Risks

**CRITICAL: Tasks T001-T005 Already Complete**
- All five tasks in PLAN.md are ALREADY FIXED in current codebase
- URLs updated, f2fs-new.sh has fsck install logic, Kbuild.sh has reboot confirmation
- **Action Required**: Confirm whether user wants re-implementation or new tasks only

**Missing Build Artifacts (HIGH)**
- No `Pifile` exists (blocks Phase 2 of plan)
- No GitHub Actions workflow (blocks Phase 5 of plan)
- No `.github/workflows/` directory structure
- **Blocker**: Cannot execute PLAN.md without these

**Incomplete Package Lists (MEDIUM)**
- `apps.sh` only adds PPA, no actual `apt install` commands
- PLAN.md references "run apps.sh logic" but script is stub
- **Risk**: Custom image will not include intended packages
- **Mitigation**: Need to extract package list from existing scripts or define new

**DietPi Base Image Acquisition (MEDIUM)**
- No download/verification logic exists
- No caching strategy implemented
- **Risk**: Workflow will fail without image acquisition step
- **Mitigation**: Workflow must implement Phase 1 of PLAN.md

**Pimod Dependency (MEDIUM)**
- No Docker setup or pimod binary in repo
- Workflow must either use pre-built pimod or build from source
- **Risk**: pimod requires QEMU/chroot capabilities in GitHub Actions runner
- **Mitigation**: Use `FROM` step in Pifile or pre-installed tooling

### Policy Decisions Needed (LOW)

**Board Targets** - User must decide:
- RPi 4, RPi 5, RPi Zero 2 W, or all three?
- Each board may need separate base image download
- Affects matrix strategy in workflow

**Release Visibility** - User must decide:
- Public releases vs private artifacts?
- Affects workflow permissions and release step

**Version Strategy** - User must decide:
- Pin DietPi version or track `latest`?
- Tag-based triggering vs manual dispatch only?

## Findings Summary

### Status: All T001-T005 Tasks Already Complete ✓

**T001** (URL fix README lines 34, 40): **DONE** - URLs already point to `dotfiles-pi`
**T002** (URL fix DIETPI_F2FS_GUIDE line 223): **DONE** - URL already correct
**T003** (Settings section README): **DONE** - Lines 43-49 fully match acceptance criteria
**T004** (fsck.f2fs install): **DONE** - Lines 433-439 implement spec exactly
**T005** (reboot confirmation): **DONE** - Lines 129-139 implement prompt with AUTO_YES

### Critical Blockers for PLAN.md Execution

1. **Missing `Pifile`** - Core customization layer undefined
2. **Missing `.github/workflows/build-image.yml`** - No automation pipeline
3. **apps.sh stub** - No package list to bake into image
4. **No image download logic** - Phase 1 of plan not implemented

### Recommended Next Actions

**IF user wants T001-T005 re-done**: Acknowledge they're already complete, verify satisfaction
**IF user wants PLAN.md execution**: Focus on blockers (Pifile, workflow, apps.sh population)
**IF user wants both**: Clarify intent - tasks vs plan are separate work streams

### Files Ready to Use (No Changes Needed)

- `RaspberryPi/f2fs-new.sh` - production-ready F2FS converter
- `RaspberryPi/Scripts/setup.sh` - hardening script for Pifile
- `RaspberryPi/docs/dietpi.txt` - template for boot partition injection
- `mise.sh` - mise installer for Pifile RUN step
- `RaspberryPi/dots/` - dotfiles directory for COPY step

### Decision Points Requiring User Input

1. **Target boards**: Which RPi models? (affects workflow matrix)
2. **Package list**: What packages should apps.sh install? (affects Pifile)
3. **Release strategy**: Public or private? Tag triggers? (affects workflow permissions)
4. **Version pinning**: Latest DietPi or pinned version? (affects maintenance burden)
