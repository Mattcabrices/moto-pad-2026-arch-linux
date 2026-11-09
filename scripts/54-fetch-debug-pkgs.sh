#!/bin/bash
# Downloads ARM packages for tablet-side debugging into /build/out/pkgs (the tablet has no internet).
# Usage: 54-fetch-debug-pkgs.sh pkg [pkg...]
R=/build/rootfs/root
mountpoint -q "$R" || mount --bind "$R" "$R"
rm -f "$R"/var/cache/pacman/pkg/*
arch-chroot "$R" pacman -Sw --noconfirm "$@" >/dev/null || exit 1
mkdir -p /build/out/pkgs
cp "$R"/var/cache/pacman/pkg/*.pkg.tar.* /build/out/pkgs/
rm -f "$R"/var/cache/pacman/pkg/*
ls -la /build/out/pkgs/ | grep -v '\.sig$'
