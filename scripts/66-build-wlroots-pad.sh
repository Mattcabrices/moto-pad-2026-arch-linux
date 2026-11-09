#!/bin/bash
# Builds wlroots 0.20.2 + archpad changes (wlroots-pad/apply.py: hybris renderer/allocator, pad backend)
# in the aarch64 rootfs. Installs to prefix /usr/local/pad. Output: /build/out/wlroots-pad.tar
# Needs scripts/64-fetch-wlroots.sh and the libhybris build (scripts/62). GPU port, see HANDOFF.md.
set -euo pipefail
R=/build/rootfs/root
mountpoint -q "$R" || mount --bind "$R" "$R"
arch-chroot "$R" pacman -S --noconfirm --needed meson ninja pkgconf wayland wayland-protocols libinput \
  libxkbcommon pixman libdrm seatd mesa libglvnd xcb-util-wm xcb-util-renderutil xcb-util-errors \
  xorg-xwayland libxcb hwdata libdisplay-info >/dev/null
# libhybris at its runtime path inside the rootfs, for linking libhybris-common.
rm -rf "$R/usr/local/hybris"; cp -a "$R/root/hb/out/usr/local/hybris" "$R/usr/local/"
# RESUME=1: keep the configured tree, refresh the archpad files, continue ninja.
if [ -z "${RESUME:-}" ]; then rm -rf "$R/root/wlr"; cp -a /build/src/wlroots-0.20.2 "$R/root/wlr"; fi
rm -rf "$R/root/wlr-out"
W=/mnt/c/mpad26/MotoPadArch/wlroots-pad
python3 $W/apply.py "$R/root/wlr"
arch-chroot "$R" env RESUME="${RESUME:-}" bash -euo pipefail -c '
cd /root/wlr
[ -n "$RESUME" ] || meson setup build --prefix=/usr/local/pad --buildtype=release -Dbackends=drm,libinput,x11 -Drenderers=gles2 \
  -Dallocators=udmabuf -Dexamples=false -Dxwayland=enabled -Dcolor-management=disabled -Dlibliftoff=disabled \
  -Dsession=enabled > /root/wlr-setup.log 2>&1 || { tail -30 /root/wlr-setup.log; exit 1; }
ninja -C build > /root/wlr-build.log 2>&1 || { grep -E "error" -A3 /root/wlr-build.log | head -60; exit 1; }
DESTDIR=/root/wlr-out ninja -C build install > /dev/null
'
# meson ignored the rpath link argument; libhybris-common/libEGL must come from /usr/local/hybris/lib.
pacman -S --noconfirm --needed patchelf >/dev/null
patchelf --set-rpath /usr/local/hybris/lib "$R/root/wlr-out/usr/local/pad/lib/libwlroots-0.20.so"
tar -C "$R/root/wlr-out" -cf /build/out/wlroots-pad.tar .
ls -la /build/out/wlroots-pad.tar; tar -tf /build/out/wlroots-pad.tar | grep "\.so" | head
