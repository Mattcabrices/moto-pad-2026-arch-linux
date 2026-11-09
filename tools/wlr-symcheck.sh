#!/bin/bash
# Lists wlroots symbols labwc needs that /build/out/wlroots-pad.tar's libwlroots does not export.
set -e
R=/build/rootfs/root
arch-chroot $R pacman -S --noconfirm --needed labwc >/dev/null 2>&1
T=$(mktemp -d); tar -C $T -xf /build/out/wlroots-pad.tar
nm -D --defined-only $T/usr/local/pad/lib/libwlroots-0.20.so | awk '{print $3}' | sort -u > $T/have
nm -D --undefined-only $R/usr/bin/labwc | awk '{print $2}' | grep '^wlr_' | sort -u > $T/need
echo "missing:"; comm -23 $T/need $T/have; rm -rf $T
