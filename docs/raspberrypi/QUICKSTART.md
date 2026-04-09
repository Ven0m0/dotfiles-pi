# DietPi F2FS Quick Start

## Setup

### Option A: Interactive

```bash
cd RaspberryPi
sudo ./f2fs-new.sh -i
```

### Option B: Flash Directly

```bash
sudo ./RaspberryPi/f2fs-new.sh --device /dev/mmcblk0
```

### Option C: Create an Image First

```bash
sudo ./RaspberryPi/f2fs-new.sh --out ~/dietpi-f2fs.img
sudo dd if=~/dietpi-f2fs.img of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

## First Boot Checklist

1. Insert the SD card into the Raspberry Pi.
2. Connect a local console if you want to watch first boot.
3. Boot the system.
4. Verify the root filesystem:

```bash
mount | grep 'on / type f2fs'
```

## Common Commands

| Task | Command |
|------|---------|
| Interactive mode | `sudo ./f2fs-new.sh -i` |
| Flash to device | `sudo ./f2fs-new.sh --device /dev/mmcblk0` |
| Create image | `sudo ./f2fs-new.sh --out image.img` |
| Customize image | `sudo ./dietpi-chroot.sh image.img` |
| Use local file | `sudo ./f2fs-new.sh --src local.img.xz --device /dev/mmcblk0` |
| Custom compression | `sudo ./f2fs-new.sh --root-opts "compress_algorithm=lz4"` |

## Troubleshooting

If the image does not boot, regenerate initramfs:

```bash
sudo ./dietpi-chroot.sh /path/to/image.img
```

## Next Steps

- Read [DIETPI_F2FS_GUIDE.md](DIETPI_F2FS_GUIDE.md) for detailed notes.
- Read [EXAMPLES.md](EXAMPLES.md) for additional command patterns.
- Review [../../dietpi.txt](../../dietpi.txt) before first boot automation.
