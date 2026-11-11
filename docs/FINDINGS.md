# Moto Pad 2026 (XT2575-4): Arch Linux bring-up findings

Recorded 2026-11-06. Nothing here has been built or booted yet.

## Device

| Item | Value | Source |
| --- | --- | --- |
| Model / product | XT2575-4, `sycamore_row_5G` | unlock repo |
| SoC | MT8755 on the MT6835 platform (Cortex-A76/A55, Mali) | TWRP tree |
| Display | 2560x1600, 90 Hz | TWRP tree |
| Bootloader | Unlocked, patched LK on `lk_a` | unlock repo |
| Kernel | `5.15.185-android13-8-00044-g051a97cf151a-ab14024729` | MotoTablets issue 8 |
| Boot image | Boot header v4, `vendor_boot` v4, A/B, 4 KiB pages | TWRP BoardConfig |
| Partition sizes | `boot` and `vendor_boot` 64 MiB, `init_boot` and `dtbo` 8 MiB, `super` 11 GiB | TWRP BoardConfig |

## What this means for the build

- **No mainline path.** I found no upstream MT6835 device tree or postmarketOS
  port. That is an absence of evidence from web searches, not a confirmed status.
  The practical base is the Android 5.15 kernel with its vendor modules.
- **The stock kernel cannot run a normal Arch userspace.** Its embedded config
  (`kernel/stock.config`, extracted from the TWRP tree's prebuilt kernel) has
  these options off: `DEVTMPFS`, `FHANDLE`, `VT`, `AUTOFS_FS`, `SYSVIPC`,
  `PID_NS`, `USER_NS`, `TMPFS_POSIX_ACL`, `FB`.
- **A rebuilt GKI kernel is the proposed route.** Build AOSP `kernel/common` at
  `051a97cf151a` with Clang 14.0.7 (r450784e) and `kernel/arch-fragment.config`.
  The kernel config has `MODVERSIONS` and `CFI_CLANG` on and `MODULE_SIG_FORCE`
  off, so stock vendor modules may still load, provided symbol CRCs and struct
  layouts stay unchanged. **This must be checked by comparing the rebuilt
  kernel's CRCs against the stock kernel's before anything is flashed.**
- **Motorola source for this exact build is not published.** Motorola said on
  2026-10-13 that it is still under internal review. The Moto Pad 60 Neo
  `Kernel-5.15.185` release is related, but it should not be assumed to match
  this firmware.

## Constraints

- Do not write `lk_a`, `lk_b`, or preloader. Do not relock.
- Do not use slot B: a report on MotoTablets issue 8 says it fails to boot after
  unlock. That is one report, but it is reason enough to stay on slot A.
- Do not run `fastboot oem device-info` or `fastboot getvar version-baseband`.
  Both wedged USB on this bootloader.
- Have stock `boot`, `init_boot`, `vendor_boot`, `dtbo`, and `vbmeta` images in
  hand before the first flash. Try `fastboot boot` first, since it writes nothing
  to the tablet; whether this LK supports it is untested.
- SP Flash Tool recovery has never been exercised on this unit.

## Expected v1 hardware support (predictions, not results)

| Area | Expectation | Reason |
| --- | --- | --- |
| Display, XFCE | Likely, software rendered | Needs the MTK DRM driver to work with Xorg |
| Touch, USB, storage, battery | Likely | Kernel drivers and sysfs |
| Wi-Fi, Bluetooth | Uncertain | MTK connectivity may need Android userspace helpers and firmware |
| Audio | Uncertain | MTK audio routing is normally driven by an Android HAL |
| GPU acceleration | Not in v1 | The Mali userspace blob is built for Android |
| Camera, GPS, cellular | Not in v1 | Depend on Android HALs |

## Decisions and current status

See the Status table in [README.md](../README.md).

## Sources

- <https://github.com/MotorolaMobilityLLC/MotoTablets/issues/8>
- <https://github.com/MotorolaMobilityLLC/MotoTablets/releases/tag/Kernel-5.15.185>
- <https://github.com/BobTheBlinker/recovery_device_motorola_sycamore_row_5G>
- <https://github.com/Mattcabrices/moto-pad-2026-xt2575-4-unlock>
- <https://android.googlesource.com/kernel/common/+/refs/heads/android13-5.15/arch/arm64/configs/gki_defconfig>
