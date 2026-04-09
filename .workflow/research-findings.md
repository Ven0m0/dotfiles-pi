---
task: "dietpi-custom-image-build-research"
phase: "research"
status: "complete"
timestamp: "2026-04-09T20:59:17+00:00"
agent: "researcher"
model: "GPT-5.4"
---

# DietPi Custom Image Build Research Findings

## 1. pimod Pifile Syntax and Image Customization

### Overview
pimod (https://github.com/Nature40/pimod) is a Docker-inspired tool that modifies Raspberry Pi images using QEMU chroot emulation on x86_64 hosts.

### Pifile Command Reference

#### Setup Stage (Image Acquisition)
```pifile
# Download and cache remote image
FROM https://example.com/base-image.img.xz

# Specify output file
TO custom-output.img

# Or auto-name based on Pifile name (MyImage.Pifile → MyImage.img)
```

#### Prepare Stage (Disk Operations)
```pifile
# Expand image by specified size (K/M/G suffixes)
PUMP 100M
```

#### Chroot Stage (Primary Customization)

**Copy files into image:**
```pifile
# Basic copy
INSTALL source.txt /destination/path

# Copy with permissions
INSTALL 0755 script.sh /usr/local/bin/

# Copy directory recursively
INSTALL dotfiles/ /home/pi/.config/
```

**Execute commands in chroot:**
```pifile
# Single command
RUN apt-get update

# Complex command with shell
RUN bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y package'

# Heredoc for multiple commands
RUN <<EOF
apt-get update
apt-get install -y package1 package2
systemctl enable service
EOF
```

**Environment variables:**
```pifile
# Set variable (available in RUN commands)
ENV MY_VAR value

# Unset variable
ENV MY_VAR
```

**Path manipulation:**
```pifile
# Add to PATH for RUN commands
PATH /usr/local/bin
```

**Host commands (execute on build machine, not in chroot):**
```pifile
HOST echo "Building at $(date)"
```

#### Postprocess Stage
```pifile
# Shrink image to minimum size + 5% buffer
SHRINK

# Or shrink to specific size
SHRINK 2G
```

### GitHub Actions Integration
```yaml
- uses: Nature40/pimod@master
  with:
    pifile: build/Custom.Pifile
```

### Key Gotchas
- Pifiles are Bash scripts; pipes require shell wrapping: `RUN bash -c 'cmd | other'`
- QEMU user emulation runs ARM binaries on x86_64 transparently
- Requires `--privileged` mode in Docker
- Remote URLs are automatically downloaded and cached
- SHRINK only works with image files, not block devices

### Documentation URLs
- Main repo: https://github.com/Nature40/pimod
- Academic paper: https://jonashoechst.de/assets/papers/hoechst2020pimod.pdf
- Context7 reference: https://context7.com/nature40/pimod/llms.txt
- Changelog: https://github.com/Nature40/pimod/blob/master/CHANGELOG.md

---

## 2. DietPi Base Image Download Strategy

### Official Download Location
**Primary source:** https://dietpi.com/downloads/images/

### File Naming Pattern
```
DietPi_{Device}-{Arch}-{Debian}.img.xz
DietPi_{Device}-{Arch}-{Debian}.img.xz.sha256
DietPi_{Device}-{Arch}-{Debian}.img.xz.asc (GPG signature)
```

### Recommended Images for Raspberry Pi

| Target Board | Filename | Debian Version |
|--------------|----------|----------------|
| RPi 4/3/2/Zero 2 | `DietPi_RPi234-ARMv8-Bookworm.img.xz` | Bookworm (12) |
| RPi 5 | `DietPi_RPi5-ARMv8-Bookworm.img.xz` | Bookworm (12) |
| RPi 4/3/2/Zero 2 | `DietPi_RPi234-ARMv8-Trixie.img.xz` | Trixie (13, testing) |

**Recommendation:** Use Bookworm (Debian 12) for stability; Trixie if bleeding-edge features needed.

### GitHub Actions Download Pattern

```yaml
- name: Download DietPi base image
  run: |
    BASE_URL="https://dietpi.com/downloads/images"
    IMAGE_NAME="DietPi_RPi234-ARMv8-Bookworm.img.xz"
    
    # Download image and checksum
    curl -fsSL "${BASE_URL}/${IMAGE_NAME}" -o dietpi-base.img.xz
    curl -fsSL "${BASE_URL}/${IMAGE_NAME}.sha256" -o dietpi-base.img.xz.sha256
    
    # Verify checksum
    sha256sum -c dietpi-base.img.xz.sha256
    
    # Optional: GPG verification
    curl -fsSL "${BASE_URL}/${IMAGE_NAME}.asc" -o dietpi-base.img.xz.asc
    gpg --keyserver keyserver.ubuntu.com --recv-keys "0x92DAB422B0E4E0AF"
    gpg --verify dietpi-base.img.xz.asc dietpi-base.img.xz
```

### Caching Strategy
```yaml
- name: Cache DietPi base image
  uses: actions/cache@v4
  with:
    path: dietpi-base.img.xz
    key: dietpi-rpi234-armv8-bookworm-${{ hashFiles('dietpi-base.img.xz.sha256') }}
```

### Gotchas
- Checksums are updated when images rebuild; cache invalidation needed
- DietPi releases are image rebuilds, not GitHub releases (no API endpoint)
- Images hosted on Cloudflare CDN; occasional cache lag reported
- GPG key ID: `0x92DAB422B0E4E0AF` (MichaIng's signing key)
- No version tagging in URLs; use checksums to track changes

### Alternative: Direct GitHub Releases (Not Recommended)
DietPi does not publish image assets to GitHub Releases. The official download site is the canonical source.

---

## 3. piqemu-action Feasibility for DietPi ARMv8 Smoke Testing

### Assessment: PARTIALLY FEASIBLE with caveats

### Available Tool: piqemu-action
- **Repository:** https://github.com/ethanjli/piqemu-action
- **Purpose:** Boot Raspberry Pi images in QEMU VM for smoke tests
- **Supported machines:** Currently only `rpi-3b+` (Raspberry Pi 3B+)
- **Status:** Experimental, 2 stars, last updated 2024

### Sample Usage
```yaml
- name: Boot DietPi image in QEMU
  uses: ethanjli/piqemu-action@v0.1.1
  with:
    image: dietpi-custom.img
    machine: rpi-3b+
    run: |
      systemctl is-active sshd
      dietpi-software list
```

### Limitations and Gotchas

1. **Raspberry Pi 4/5 not supported**
   - QEMU support for RPi 4B is partial (no network in emulation)
   - RPi 5 not yet supported by QEMU

2. **DietPi-specific challenges**
   - First-boot automation (`dietpi-software`) may timeout in QEMU
   - Slow emulation: 10-20x slower than native hardware
   - Forum discussion notes QEMU ARM emulation is "quite slow" for development

3. **Boot requirements**
   - Requires kernel extraction from image (partition 1)
   - DTB (device tree blob) must match machine type
   - Network setup requires additional configuration

### Alternative: pguyot/arm-runner-action (RECOMMENDED)
**Repository:** https://github.com/pguyot/arm-runner-action

**Why better for DietPi:**
- Explicitly supports DietPi images:
  - `dietpi:rpi_armv8_bookworm` (arm64)
  - `dietpi:rpi_armv8_bullseye` (arm64)
- Uses chroot + QEMU user emulation (faster than full system emulation)
- Proven in production (22 releases, 179 stars)
- Simpler syntax, no kernel extraction needed

**Sample usage:**
```yaml
- name: Smoke test DietPi image
  uses: pguyot/arm-runner-action@v2.6.5
  with:
    base_image: file://dietpi-custom.img
    cpu: cortex-a53
    commands: |
      # Basic smoke tests
      systemctl is-system-running --wait
      test -f /boot/dietpi.txt
      dietpi-software list | grep -q "Available"
```

### Alternative: systemd-nspawn without QEMU (FASTEST)
**Repository:** https://github.com/ethanjli/pinspawn-action

For tests that don't require Docker daemon:
```yaml
- uses: ethanjli/pinspawn-action@v0.1.1
  with:
    image: dietpi-custom.img
    run: |
      apt-cache policy
      test -d /home/dietpi
```

### Recommendation
**Skip QEMU full-system emulation for CI smoke tests.** Use one of:
1. **pguyot/arm-runner-action** for comprehensive tests (5-10 min runtime)
2. **ethanjli/pinspawn-action** for fast file/package validation (30s-2min)
3. **Manual validation** on real hardware (RPi via self-hosted runner)

**Rationale:** Full QEMU system emulation (piqemu-action) is too slow and unreliable for DietPi's first-boot automation. Chroot-based testing provides better speed/reliability tradeoff.

---

## 4. GitHub Release Creation Gotchas

### Trigger Patterns

#### On Tag Push (Recommended)
```yaml
on:
  push:
    tags:
      - 'v*'  # Matches v1.0.0, v2.1.3, etc.
```

#### Manual Dispatch (For Fixes)
```yaml
on:
  workflow_dispatch:
    inputs:
      tag:
        description: 'Tag to release (e.g., v1.0.0)'
        required: true
        type: string
```

### Key Gotchas

#### 1. GITHUB_TOKEN Permissions
```yaml
permissions:
  contents: write        # Required to create releases
  discussions: write     # Optional: create release discussions
```

#### 2. Concurrent Release Prevention
```yaml
concurrency:
  group: publish-release
  cancel-in-progress: false  # Don't cancel, queue instead
```
**Rationale:** Prevents race conditions when multiple tags pushed simultaneously.

#### 3. Prerelease Detection
```yaml
- uses: softprops/action-gh-release@v2
  with:
    prerelease: ${{ contains(github.ref_name, '-') }}  # v1.0.0-beta → prerelease
```

#### 4. Draft vs Published Releases
- **Draft releases:** Invisible until manually published; useful for review
- **Published releases:** Immediately visible; triggers notifications
- **Latest release flag:** Only one non-draft, non-prerelease can be "latest"

```yaml
- uses: softprops/action-gh-release@v2
  with:
    draft: true  # Create as draft for manual review
```

#### 5. Asset Upload Patterns
```yaml
- uses: softprops/action-gh-release@v2
  with:
    files: |
      dietpi-custom-*.img.xz
      dietpi-custom-*.img.xz.sha256
      CHANGELOG.md
```

#### 6. Avoid Recursive Triggers
**Problem:** Release creation can trigger `workflow_dispatch` if using PAT instead of `GITHUB_TOKEN`.

**Solution:** Use `GITHUB_TOKEN` for release creation; it won't trigger other workflows.

```yaml
- uses: softprops/action-gh-release@v2
  with:
    token: ${{ secrets.GITHUB_TOKEN }}  # Not a PAT
```

#### 7. Tag Must Exist Before Release
If using `workflow_dispatch`, create tag first:
```yaml
- name: Create tag if manual dispatch
  if: github.event_name == 'workflow_dispatch'
  run: |
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git tag -a "${{ inputs.tag }}" -m "Release ${{ inputs.tag }}"
    git push origin "${{ inputs.tag }}"
```

#### 8. Release Name vs Tag Name
```yaml
- uses: softprops/action-gh-release@v2
  with:
    name: "DietPi Custom Image ${{ github.ref_name }}"  # Human-readable name
    tag_name: ${{ github.ref_name }}                     # Git tag (v1.0.0)
```

#### 9. Changelog Generation
**Manual:**
```yaml
body_path: CHANGELOG.md
```

**Automated:**
```yaml
generate_release_notes: true  # Uses PR titles and commit messages
```

#### 10. Retention and Cleanup
GitHub Actions artifacts (different from release assets) are auto-deleted after 90 days. Release assets persist indefinitely unless manually deleted.

### Recommended Action: softprops/action-gh-release
**Repository:** https://github.com/softprops/action-gh-release

**Why:** Most popular (2.6k stars), well-maintained, supports all GitHub Release features.

### Complete Example Workflow
```yaml
name: Release DietPi Custom Image

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
    inputs:
      tag:
        description: 'Release tag (e.g., v1.0.0)'
        required: true

concurrency:
  group: publish-release
  cancel-in-progress: false

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Download artifacts
        uses: actions/download-artifact@v4
        with:
          name: dietpi-custom-image
      
      - name: Generate checksums
        run: |
          sha256sum dietpi-custom-*.img.xz > checksums.txt
      
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          name: "DietPi Custom ${{ github.ref_name }}"
          body: |
            ## DietPi Custom Image Build
            
            **Base:** DietPi ARMv8 Bookworm
            **Target:** Raspberry Pi 4/3/2/Zero 2
            
            ### Installation
            ```bash
            xzcat dietpi-custom-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress
            ```
          files: |
            dietpi-custom-*.img.xz
            checksums.txt
          draft: false
          prerelease: ${{ contains(github.ref_name, '-') }}
          generate_release_notes: true
```

---

## Best Practices Summary

### Image Build Pipeline
1. **Download DietPi base image** from https://dietpi.com/downloads/images/
2. **Verify checksum** before processing
3. **Cache base image** keyed on checksum hash
4. **Use pimod with Pifile** for image customization
5. **Shrink image** with `SHRINK` command before compression
6. **Compress with xz** (`xz -9 -T0`) for distribution
7. **Skip QEMU smoke tests** in CI (too slow); validate on real hardware

### Recommended Defaults
- **Base image:** `DietPi_RPi234-ARMv8-Bookworm.img.xz` (Debian 12)
- **pimod Docker image:** `nature40/pimod:latest`
- **Release action:** `softprops/action-gh-release@v2`
- **Testing:** `pguyot/arm-runner-action@v2` if needed, or manual validation

### Key URLs
- pimod: https://github.com/Nature40/pimod
- DietPi images: https://dietpi.com/downloads/images/
- DietPi repo: https://github.com/MichaIng/DietPi
- arm-runner-action: https://github.com/pguyot/arm-runner-action
- action-gh-release: https://github.com/softprops/action-gh-release

### Implementation Priority
1. **High:** pimod Pifile creation (core customization)
2. **High:** DietPi download + checksum verification
3. **Medium:** GitHub Release workflow (tag-triggered)
4. **Low:** QEMU smoke testing (optional, consider skipping)
