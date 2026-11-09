#!/bin/bash
# Re-packs /build/out/wlroots-pad.tar with RUNPATH /usr/local/hybris/lib on libwlroots (one-off fix for the first build).
set -e
pacman -S --noconfirm --needed patchelf >/dev/null
R=/build/rootfs/root
patchelf --set-rpath /usr/local/hybris/lib "$R/root/wlr-out/usr/local/pad/lib/libwlroots-0.20.so"
readelf -d "$R/root/wlr-out/usr/local/pad/lib/libwlroots-0.20.so" | grep -E "RUNPATH|RPATH"
tar -C "$R/root/wlr-out" -cf /build/out/wlroots-pad.tar .
