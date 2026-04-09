# Raspberry Pi Scripts

This section covers the Raspberry Pi and DietPi scripts that remain in active use in this repository.

## Layout

```text
RaspberryPi/
├── PiClean.sh         # System cleanup script
├── Scripts/
│   ├── apkg.sh        # Interactive APT package helper
│   ├── blocklist.sh   # hblock wrapper
│   ├── Kbuild.sh      # Kernel build helper
│   ├── pi-minify.sh   # System minimization helper
│   ├── pi_hole_updater.sh
│   ├── podman-docker.sh
│   ├── setup.sh       # Initial system setup
│   └── sqlite-tune.sh
├── dietpi-chroot.sh   # DietPi image chroot helper
├── dots/              # Dotfiles and config snippets
├── f2fs-new.sh        # Image-to-F2FS conversion helper
├── raspi-f2fs.sh      # Device flashing helper
└── update.sh          # System update script
```

## Quick Start Scripts

### Update

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/update.sh | bash
```

### Clean

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/dotfiles-pi/refs/heads/main/RaspberryPi/PiClean.sh | bash
```

## Recommended Post-Install Checks

- Use `dietpi-config` to set hostname, locale, timezone, and other DietPi-managed options.
- Enable IPv4 forwarding only on systems that route traffic:

```bash
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

- Verify SSH key-based access before disabling password authentication.
- If you prefer `nala`, install it and refresh mirror selection:

```bash
sudo apt install nala
sudo nala fetch
```

## F2FS Documentation

- [QUICKSTART.md](QUICKSTART.md)
- [DIETPI_F2FS_GUIDE.md](DIETPI_F2FS_GUIDE.md)
- [EXAMPLES.md](EXAMPLES.md)
- Canonical DietPi automation template: [../../dietpi.txt](../../dietpi.txt)

## Reference Links

- [reference/REFERENCES.md](reference/REFERENCES.md)
