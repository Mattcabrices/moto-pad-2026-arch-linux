#!/bin/bash
# Deletes large build artefacts that can be regenerated, then trims the filesystem so a sparse
# WSL virtual disk can return the space to Windows. Keeps the kernel tree, toolchain, rootfs and
# the images in out/ (boot-archpad.img, userdata-archpad.simg).
cd /
rm -rf /build/out/android-full /build/out/android-full.tar   # GPU staging (scripts/61)
rm -rf /build/kernel/out-userns /build/kernel/probe          # USER_NS test, KMI bisect
rm -f  /build/out/userdata-archpad.raw                       # raw image (the .simg is kept)
rm -rf /build/stock/android-work                             # APEX unpack scratch
rm -rf /build/stock/system.d                                 # 3 GB system.img extract (scripts/56 redoes it)
rm -f  /build/rootfs/ArchLinuxARM-aarch64-latest.tar.gz*     # re-downloadable
rm -f  /build/out/xstrace*.log /build/out/live-dmesg.log /build/out/screen.xwd
rm -rf /build/kernel/out/.tmp_* 2>/dev/null
pacman -Scc --noconfirm >/dev/null 2>&1
fstrim -av 2>/dev/null | tail -1
df -h / | tail -1
du -sh /build 2>/dev/null
