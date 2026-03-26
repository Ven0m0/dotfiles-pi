# Implementation Plan
_Generated: 2026-03-26 · 5 tasks · Est. S×4, M×1_

## Summary

Marker extraction across the dotfiles-pi repository surfaced four categories of actionable debt: stale cross-repo URLs in documentation (scripts still reference the old `Ven0m0/Linux-OS` origin), an incomplete documentation stub for network/package settings, a runtime-path gap in `f2fs-new.sh` when `fsck.f2fs` is absent, and a missing interactive confirmation in `Kbuild.sh` before the post-install reboot.
All five tasks are purely documentation or single-script changes; none require structural refactoring or new dependencies.

## Task Index (topological order)

| #  | ID   | Title                                                       | Sev    | Cat      | Size | Blocks       |
|----|------|-------------------------------------------------------------|--------|----------|------|--------------|
| 1  | T001 | Fix stale Linux-OS URLs in RaspberryPi/README.md            | high   | docs     | S    | —            |
| 2  | T002 | Fix stale Linux-OS project URL in DIETPI_F2FS_GUIDE.md      | medium | docs     | S    | —            |
| 3  | T003 | Complete "Settings todo" stub in RaspberryPi/README.md      | medium | docs     | S    | —            |
| 4  | T004 | Install fsck.f2fs in rootfs when missing in f2fs-new.sh     | high   | bug      | M    | —            |
| 5  | T005 | Add reboot confirmation prompt to Kbuild.sh                 | medium | refactor | S    | —            |

---

## Tasks

### T001 · Fix stale Linux-OS URLs in RaspberryPi/README.md

**File:** `RaspberryPi/README.md:34` and `RaspberryPi/README.md:40`
**Severity:** high · **Category:** docs · **Size:** S
**Blocks:** — · **Blocked by:** —

**Context:**
```
### Quick Start Scripts

curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/update.sh | bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/PiClean.sh | bash
```

**Intent:** After the migration from `Ven0m0/Linux-OS` to `Ven0m0/dotfiles-pi`, the Quick Start curl commands in the README were not updated to point at the new canonical repo.

**Acceptance criteria:**
- [ ] Line 34: URL base changed from `Ven0m0/Linux-OS/refs/heads/main` to `Ven0m0/dotfiles-pi/refs/heads/main`.
- [ ] Line 40: URL base changed from `Ven0m0/Linux-OS/refs/heads/main` to `Ven0m0/dotfiles-pi/refs/heads/main`.
- [ ] Both resulting URLs follow the pattern `https://raw.githubusercontent.com/Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/<script>.sh`.
- [ ] No other lines in `RaspberryPi/README.md` are modified.

**Implementation:**
```
sed -i 's|Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/update.sh|Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/update.sh|' RaspberryPi/README.md
sed -i 's|Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/PiClean.sh|Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/PiClean.sh|' RaspberryPi/README.md
```

---

### T002 · Fix stale Linux-OS project URL in DIETPI_F2FS_GUIDE.md

**File:** `RaspberryPi/DIETPI_F2FS_GUIDE.md:224`
**Severity:** medium · **Category:** docs · **Size:** S
**Blocks:** — · **Blocked by:** —

**Context:**
```
- Project repo: https://github.com/Ven0m0/Linux-OS
```

**Intent:** The F2FS guide retains a footer pointing at the old source repository; readers following the link land at a different repo from where the scripts actually live.

**Acceptance criteria:**
- [ ] Line 224 URL updated to `https://github.com/Ven0m0/dotfiles-pi`.
- [ ] No other content on that line changes.
- [ ] Surrounding lines in the file are not modified.

**Implementation:**
```
sed -i 's|https://github.com/Ven0m0/Linux-OS|https://github.com/Ven0m0/dotfiles-pi|' RaspberryPi/DIETPI_F2FS_GUIDE.md
```

---

### T003 · Complete "Settings todo" stub in RaspberryPi/README.md

**File:** `RaspberryPi/README.md:43–47`
**Severity:** medium · **Category:** docs · **Size:** S
**Blocks:** — · **Blocked by:** —

**Context:**
```markdown
### Settings todo

```markdown
net.ipv4.ip_forward=1
https://gitlab.com/volian/nala/-/blob/main/docs/nala-fetch.8.rst?ref_type=heads
```
```

**Intent:** The author left a raw placeholder noting two post-install settings to document: enabling IPv4 forwarding (required for routing/VPN use cases) and configuring `nala` as an apt front-end. The section has no prose, no commands, and an incorrect fenced-code language tag (`markdown` instead of `bash` or `ini`).

**Acceptance criteria:**
- [ ] Section heading renamed from `### Settings todo` to `### Recommended post-install settings` (or equivalent imperative heading).
- [ ] `net.ipv4.ip_forward=1` presented as a sysctl command (`sudo sysctl -w net.ipv4.ip_forward=1`) or as a `/etc/sysctl.d/` snippet with a brief explanation.
- [ ] `nala` fetch link replaced by a one-liner install command plus a pointer to the nala-fetch man page URL.
- [ ] Code blocks use the correct language tag (`bash` or `ini`).
- [ ] No other sections in the file are modified.

**Implementation:**
Replace lines 43–49 with:
```markdown
### Recommended post-install settings

Enable IPv4 forwarding (required for VPN/routing):
```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

Use [nala](https://gitlab.com/volian/nala) as a friendlier apt front-end:
```bash
sudo apt install nala
sudo nala fetch   # choose fastest mirrors
```
```

---

### T004 · Install fsck.f2fs in rootfs when missing in f2fs-new.sh

**File:** `RaspberryPi/f2fs-new.sh:433–436`
**Severity:** high · **Category:** bug · **Size:** M
**Blocks:** — · **Blocked by:** —

**Context:**
```bash
# Basic warning: fsck.f2fs may not exist; not fatal for boot
if [[ ! -x "$DST_MNT_ROOT/sbin/fsck.f2fs" && ! -x "$DST_MNT_ROOT/usr/sbin/fsck.f2fs" ]]; then
  log "WARN: fsck.f2fs not found in rootfs. Boot should still work; fsck service (if any) may complain.\n"
fi
```

**Intent:** The script converts a root filesystem to F2FS but does not ensure `f2fs-tools` (which provides `fsck.f2fs`) is installed inside the new rootfs. On first boot the systemd `systemd-fsck@.service` unit will fail if `fsck.f2fs` is absent, producing boot-time errors and potentially triggering emergency mode on strict configurations.

**Acceptance criteria:**
- [ ] When `fsck.f2fs` is absent, the script attempts to install `f2fs-tools` into the rootfs via `chroot "$DST_MNT_ROOT" apt-get install -y f2fs-tools` (requires network or local cache to be available during conversion).
- [ ] If the chroot install fails (non-zero exit), the existing WARN message is still emitted and execution continues (non-fatal path preserved).
- [ ] A comment above the block explains why `f2fs-tools` is needed at first boot.
- [ ] `bash -n RaspberryPi/f2fs-new.sh` and `shellcheck RaspberryPi/f2fs-new.sh` pass after the change.
- [ ] The fallback WARN log line is preserved so users are informed when automatic install also fails.

**Implementation:**
Replace the existing `if` block at lines 433–436 with:
```bash
# f2fs-tools provides fsck.f2fs; required by systemd-fsck@.service on first boot
if [[ ! -x "$DST_MNT_ROOT/sbin/fsck.f2fs" && ! -x "$DST_MNT_ROOT/usr/sbin/fsck.f2fs" ]]; then
  log "fsck.f2fs not found — attempting to install f2fs-tools into rootfs …\n"
  if ! chroot "$DST_MNT_ROOT" apt-get install -y --no-install-recommends f2fs-tools 2>/dev/null; then
    log "WARN: f2fs-tools install failed. Boot should still work; fsck service (if any) may complain.\n"
  fi
fi
```

---

### T005 · Add reboot confirmation prompt to Kbuild.sh

**File:** `RaspberryPi/Scripts/Kbuild.sh:7` and surrounding install section
**Severity:** medium · **Category:** refactor · **Size:** S
**Blocks:** — · **Blocked by:** —

**Context:**
```bash
# WARNING: This script will reboot the system after kernel installation
```
(also repeated in the `usage()` heredoc at line 46)

**Intent:** The author documented the reboot side-effect in a comment and in `--help` output, but the script does not ask for confirmation before rebooting. A user who runs the script unaware or on a remote machine will lose their session without warning.

**Acceptance criteria:**
- [ ] Before executing `reboot` (or `systemctl reboot`), the script prints the warning and prompts `Reboot now? [y/N]:`.
- [ ] If the user answers anything other than `y` or `Y`, the script prints `Reboot skipped. Reboot manually to load the new kernel.` and exits 0.
- [ ] The prompt is bypassed when a `-y` / `--yes` flag is passed (or when `stdin` is not a TTY, i.e., `[[ ! -t 0 ]]`), so non-interactive callers are not broken.
- [ ] `bash -n RaspberryPi/Scripts/Kbuild.sh` and `shellcheck RaspberryPi/Scripts/Kbuild.sh` pass after the change.
- [ ] The existing `WARNING` comment at line 7 and in `usage()` is kept.

**Implementation:**
Locate the `reboot` call in `Kbuild.sh`. Replace it with:
```bash
_confirm_reboot() {
  if [[ ${AUTO_YES:-0} -eq 1 || ! -t 0 ]]; then
    return 0
  fi
  read -r -p "$(warn 'Reboot now to load the new kernel? [y/N]: ')" _ans
  [[ ${_ans,,} == y ]] || { log "Reboot skipped. Run: sudo reboot"; exit 0; }
}
_confirm_reboot
sudo reboot
```
Add `AUTO_YES=0` near the top of the script and set it to `1` when `-y`/`--yes` is parsed in the argument loop.
