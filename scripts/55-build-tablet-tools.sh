#!/bin/bash
# Compiles small ARM helper programs for the tablet inside the aarch64 build rootfs (via qemu).
# gcc is installed into the build rootfs only for this and removed afterwards to keep it lean.
set -e
R=/build/rootfs/root
S=/mnt/c/mpad26/MotoPadArch/tools/src
mountpoint -q "$R" || mount --bind "$R" "$R"
arch-chroot "$R" pacman -S --noconfirm --needed gcc >/dev/null
mkdir -p "$R/root/src"; cp "$S"/*.c "$R/root/src/"
arch-chroot "$R" sh -c 'cd /root/src && gcc -O2 -o kmstest kmstest.c -I/usr/include/libdrm -ldrm && gcc -O2 -shared -fPIC -o noplanes.so noplanes.c -I/usr/include/libdrm -ldl'
mkdir -p /build/out/tools
cp "$R"/root/src/kmstest "$R"/root/src/noplanes.so /build/out/tools/
rm -rf "$R/root/src"
arch-chroot "$R" pacman -Rns --noconfirm gcc >/dev/null || true
rm -f "$R"/var/cache/pacman/pkg/*
file /build/out/tools/*
