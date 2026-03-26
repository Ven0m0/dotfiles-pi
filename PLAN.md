# Raspberry Pi / DietPi Image Build & Customization Plan

This plan outlines an automated workflow for creating, customizing, and managing Raspberry Pi and DietPi images using various open-source tools.

## Phase 1: Image Generation & Base Customization

### 1.1 Base Image Generation
- Use **[pi-gen-action](https://github.com/usimd/pi-gen-action)** for creating official-style Raspberry Pi OS images from scratch.
- Utilize **[dietpiconfig](https://github.com/adamdrake/dietpiconfig)** (Web GUI) to generate `dietpi.txt` for automated DietPi installations.

### 1.2 Image Customization (CI/CD)
- Integrate **[pimod](https://github.com/Nature40/pimod)** to use `Pifile` for Docker-like image modification (installing packages, setting up users, etc.).
- Use **[CustoPiZer](https://github.com/OctoPrint/CustoPiZer)** for specialized customizations (e.g., OctoPrint-style images).
- Implement **[pinspawn-action](https://github.com/ethanjli/pinspawn-action)** in GitHub Actions for fast, containerized customization of existing images using `systemd-nspawn`.
- Use **[piqemu-action](https://github.com/ethanjli/piqemu-action)** when full virtualization is required (e.g., interacting with the Docker daemon during the build process).

## Phase 2: Software Stack Deployment

### 2.1 NAS & Download Station
- Deploy **[DietPi-Download-Station](https://github.com/lishuren/DietPi-Download-Station)** for an automated NAS setup including Aria2, VPN (Mihomo), and Samba.

### 2.2 Monitoring & Management
- Install **[DietPi-Dashboard](https://github.com/nonnorm/DietPi-Dashboard)** for a lightweight web-based management interface.

## Phase 3: Post-Migration & Maintenance

### 3.1 Integrated Scripts (from Ven0m0/Linux-OS)
- Maintain and update the migrated scripts in the `RaspberryPi/` directory:
  - `f2fs-new.sh` / `raspi-f2fs.sh`: Filesystem optimization for SD card longevity.
  - `PiClean.sh`: System cleanup.
  - `update.sh`: Automated system updates.
  - `Scripts/setup.sh`: Initial system hardening and setup.

## Workflow Summary
1. **Define** requirements in `dietpi.txt` or a `Pifile`.
2. **Build/Customize** the image via GitHub Actions using **pi-gen-action**, **pimod**, or **pinspawn-action**.
3. **Deploy** the customized image to the Raspberry Pi.
4. **Manage** the running system via **DietPi-Dashboard** and **DietPi-Download-Station**.
5. **Optimize** using the local script collection (`f2fs`, `PiClean`, etc.).
