# dotfiles-pi
My raspberry pi debian dotfiles and stuff

## Key Components

- **[RaspberryPi/](RaspberryPi/)**: A collection of scripts and configurations for Raspberry Pi and DietPi, migrated from [Ven0m0/Linux-OS](https://github.com/Ven0m0/Linux-OS).
- **[docs/PLAN.md](docs/PLAN.md)**: A detailed implementation plan for automated image building and customization.
- **[Pifile](Pifile)** and **[dietpi.txt](dietpi.txt)**: Image customisation and first-boot automation inputs for DietPi builds.
- **[.github/workflows/build-image.yml](.github/workflows/build-image.yml)**: GitHub Actions pipeline for building and releasing custom DietPi images.
- **[apps.sh](apps.sh)**: APT/PPA bootstrap helper script.
- **[mise.sh](mise.sh)**: Installer for `mise` tool manager.

## Projects Integrated

- [dietpiconfig](https://github.com/adamdrake/dietpiconfig)
- [DietPi-Dashboard](https://github.com/nonnorm/DietPi-Dashboard)
- [DietPi-Download-Station](https://github.com/lishuren/DietPi-Download-Station)
- [pimod](https://github.com/Nature40/pimod)
- [CustoPiZer](https://github.com/OctoPrint/CustoPiZer)
- [piqemu-action](https://github.com/ethanjli/piqemu-action)
- [pinspawn-action](https://github.com/ethanjli/pinspawn-action)
- [pi-gen-action](https://github.com/usimd/pi-gen-action)
