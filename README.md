# dotfiles-pi

Bootstrap scripts, dotfiles, and image-build inputs for Raspberry Pi, Debian, and DietPi.

## Key Components

- **[RaspberryPi/](RaspberryPi/)**: Active Raspberry Pi and DietPi scripts, dotfiles, and build helpers.
- **[docs/raspberrypi/](docs/raspberrypi/)**: Raspberry Pi usage guides and reference notes.
- **[docs/PLAN.md](docs/PLAN.md)**: High-level plan for the custom DietPi image workflow.
- **[Pifile](Pifile)** and **[dietpi.txt](dietpi.txt)**: Image customization and first-boot automation inputs for DietPi builds.
- **[.github/workflows/build-image.yml](.github/workflows/build-image.yml)**: GitHub Actions workflow for building and releasing custom DietPi images.
- **[apps.sh](apps.sh)**: APT/PPA bootstrap helper.
- **[mise.sh](mise.sh)**: `mise` installer.

## Projects Referenced

- [dietpiconfig](https://github.com/adamdrake/dietpiconfig)
- [DietPi-Dashboard](https://github.com/nonnorm/DietPi-Dashboard)
- [DietPi-Download-Station](https://github.com/lishuren/DietPi-Download-Station)
- [pimod](https://github.com/Nature40/pimod)
- [CustoPiZer](https://github.com/OctoPrint/CustoPiZer)
- [piqemu-action](https://github.com/ethanjli/piqemu-action)
- [pinspawn-action](https://github.com/ethanjli/pinspawn-action)
- [pi-gen-action](https://github.com/usimd/pi-gen-action)
