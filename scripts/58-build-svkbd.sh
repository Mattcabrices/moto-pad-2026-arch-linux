#!/bin/bash
# Builds svkbd (suckless on-screen keyboard for X11, made for Linux phones) for the tablet.
# Output: /build/out/tools/svkbd-mobile-intl
set -e
R=/build/rootfs/root
V=0.4.2
mountpoint -q "$R" || mount --bind "$R" "$R"
mkdir -p /build/src && cd /build/src
[ -f svkbd-$V.tar.gz ] || curl -fsSL -m 120 -o svkbd-$V.tar.gz https://dl.suckless.org/tools/svkbd-$V.tar.gz
sha256sum svkbd-$V.tar.gz
rm -rf "$R/root/svkbd"; mkdir -p "$R/root/svkbd"
tar -xzf svkbd-$V.tar.gz -C "$R/root/svkbd" --strip-components 1
arch-chroot "$R" pacman -S --noconfirm --needed gcc make pkgconf libxtst libxinerama libxft >/dev/null
arch-chroot "$R" sh -c 'cd /root/svkbd && make LAYOUT=mobile-intl >/dev/null'
mkdir -p /build/out/tools
install -m755 "$R/root/svkbd/svkbd-mobile-intl" /build/out/tools/
rm -rf "$R/root/svkbd"
arch-chroot "$R" pacman -Rns --noconfirm gcc make >/dev/null || true
rm -f "$R"/var/cache/pacman/pkg/*
file /build/out/tools/svkbd-mobile-intl | cut -c1-90
