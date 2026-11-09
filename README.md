# Arch Linux on the Moto Pad 2026 (Lenovo Idea Tab)

A lightweight Arch Linux ARM + XFCE system for the **Motorola Moto Pad 2026** (XT2575-4, `sycamore_row_5G`,
MediaTek Dimensity 6300 / MT6835, Mali-G57 MC2), running from the tablet's internal storage with the stock
Android vendor kernel modules. The Moto Pad 2026 is a rebrand of the **Lenovo Idea Tab**; that tablet will likely
need only small changes, but this has only been tested on the XT2575-4.

By **Matt Cabrices**, built with Claude Code (Anthropic), November 2026.

Bootloader unlock (a prerequisite): [moto-pad-2026-xt2575-4-unlock](https://github.com/Mattcabrices/moto-pad-2026-xt2575-4-unlock).

## Status

| Area | State |
| --- | --- |
| Boot | Rebuilt Android GKI kernel `5.15.185-archpad` in `boot_a`, Arch on `userdata` (ext4), boot-loop breaker with a telnet rescue console |
| Display and touch | 1600x2560 @ 90 Hz panel, used in landscape; Himax touchscreen |
| Desktop | XFCE. Default: **GPU-composited Wayland session** (labwc on the Mali GPU through libhybris). Fallback: Xorg |
| GPU | Compositing on the GPU, zero-copy scanout. Apps still render on the CPU (GPU rendering for apps is in progress) |
| Wi-Fi, Bluetooth | Working, through MediaTek's Android helpers run in a small chroot with a property shim |
| Audio | Speakers and the main microphone. Headphone jack not done yet |
| USB | Network gadget (SSH over USB) |
| Not working | Camera, modem, headphone jack |

## How it works (short version)

- **Kernel:** AOSP `kernel/common` rebuilt with Arch-friendly options (`kernel/arch-fragment.config`) while keeping
  the symbol CRCs, so the 300+ stock vendor modules (display, touch, Wi-Fi, audio, GPU) still load.
- **Android pieces without Android:** the stock system/vendor images are mounted read-only at `/opt/android-full`.
  `servicemanager`, `hwservicemanager`, `vndservicemanager` and MediaTek's gralloc allocator run in a chroot as
  systemd units (`config/android-units/`), with `tools/src/propshim.c` standing in for Android's property service
  and `tools/fake-logd.py` for logd.
- **GPU:** [libhybris](https://github.com/libhybris/libhybris) loads the Mali EGL/GLES blob. A patched wlroots 0.20
  (`wlroots-pad/`) adds a `hybris` renderer, an AHardwareBuffer allocator and a minimal `pad` display backend
  that sticks to the KMS calls the vendor display driver handles safely. labwc runs on top; XFCE's panel and
  desktop run inside it.
- No vendor binaries or stock images are included in this repository. The scripts extract what they need from
  your own device's firmware.

## Layout

| Path | Contents |
| --- | --- |
| `scripts/` | Numbered build steps, run in WSL2 (Arch) on Windows: host setup, unpack stock, kernel, rootfs, images, flashing via mtkclient, libhybris, wlroots |
| `tools/` | Helpers (SSH/USB networking, flashing, screenshots) and `tab-*.sh` scripts run on the tablet as root via `tools/pad-sudo.sh` |
| `tools/src/` | Small C programs: property shim, GPU tests, KMS tests |
| `wlroots-pad/` | Patches and new files for wlroots 0.20.2 (`apply.py`) |
| `config/` | labwc session files and the Android-service systemd units |
| `kernel/` | Stock kernel config and the Arch config fragment |
| `docs/FINDINGS.md` | Device research |
| `HANDOFF.md` | Detailed working log: every fix, gotcha and open item |

## Warnings

- This wipes Android's `userdata`. You need an unlocked bootloader and must accept the risk of bricking.
- A fresh image's `matt` and `root` passwords are `archpad`. **Change them.** `tools/pad-sudo.sh` reads the current
  password from `tools/.pad-password` (git-ignored).
- Paths in the scripts assume the project lives at `C:\mpad26\MotoPadArch` and WSL distro `archlinux`.

## License

MIT for the code in this repository (see `LICENSE`). wlroots, libhybris, the Linux kernel and the Android/MediaTek
firmware keep their own licenses.
