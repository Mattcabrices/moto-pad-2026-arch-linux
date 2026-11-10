#!/bin/bash
# Builds libhybris (pinned in scripts/60) for arm64 in the aarch64 build rootfs (qemu), with
# Mali quirks and the Wayland EGL platform. Output: /build/out/libhybris.tar (prefix /usr/local/hybris).
set -euo pipefail
R=/build/rootfs/root
mountpoint -q "$R" || mount --bind "$R" "$R"
# RESUME=1: keep the existing tree and objects, just continue make.
if [ -z "${RESUME:-}" ]; then
  rm -rf "$R/root/hb"; mkdir -p "$R/root/hb"
  cp -a /build/src/libhybris "$R/root/hb/libhybris"
  cp -a /build/src/android-headers "$R/root/hb/android-headers"
fi
# archpad hook additions: bionic functions that read bionic TLS (absent on glibc threads) are routed
# to glibc. One entry per crash found; see HANDOFF.md "GPU port".
H="$R/root/hb/libhybris/hybris/common/hooks.c"
EXTRA_HOOKS="__ctype_get_mb_cur_max"
for f in $EXTRA_HOOKS; do
  grep -q "HOOK_DIRECT_NO_DEBUG($f)" "$H" || sed -i "s|^    HOOK_DIRECT(uselocale),|&\n    HOOK_DIRECT_NO_DEBUG($f), /* archpad */|" "$H"
done
# Working property find/read hooks (see scripts/libhybris-archpad-props.c).
if ! grep -q archpad_property_find "$H"; then
  n=$(grep -n '^static struct _hook ' "$H" | head -1 | cut -d: -f1)   # before the first hook table
  sed -i "$((n - 1))r /mnt/c/mpad26/MotoPadArch/scripts/libhybris-archpad-props.c" "$H"
  # hooks_properties is skipped for SDK >= 27, so add these to hooks_common (after uselocale).
  sed -i 's|^    HOOK_DIRECT(uselocale),|&\n    HOOK_TO(__system_property_find, archpad_property_find), /* archpad */\n    HOOK_TO(__system_property_read, archpad_property_read), /* archpad */\n    HOOK_TO(__system_property_read_callback, archpad_property_read_callback), /* archpad */\n    HOOK_TO(__system_property_get, archpad_property_get), /* archpad */|' "$H"
fi
grep -c "/\* archpad \*/" "$H"
# Compositor side of android_wlegl: server_wlegl_buffer_from() trusted any wl_resource's user data, so asking
# eglQueryWaylandBufferWL about a wl_shm/dmabuf buffer would misread it. wlroots-pad uses that query to recognise
# GPU client buffers, so only accept libhybris' own wl_buffers.
W="$R/root/hb/libhybris/hybris/platforms/common/server_wlegl_buffer.cpp"
grep -q archpad "$W" || perl -0pi -e 's/(server_wlegl_buffer_from\(struct wl_resource \*buffer\)\n\{\n\tif \(!buffer\)\n\t\treturn NULL;\n)/$1\t\/* archpad: only libhybris wl_buffers *\/\n\tif (!wl_resource_instance_of(buffer, &wl_buffer_interface, &server_wlegl_buffer_impl))\n\t\treturn NULL;\n/' "$W"
grep -c archpad "$W"
# libhybris implements eglGetPlatformDisplayEXT/eglCreatePlatformWindowSurfaceEXT but does not list
# EGL_EXT_platform_base among the client extensions; mpv (and other EGL 1.4 clients) refuse to start without it.
E="$R/root/hb/libhybris/hybris/egl/egl.c"
grep -q '"EGL_EXT_client_extensions EGL_EXT_platform_base ' "$E" || \
  sed -i 's/"EGL_EXT_client_extensions EGL_EXT_platform_wayland EGL_KHR_platform_wayland"/"EGL_EXT_client_extensions EGL_EXT_platform_base EGL_EXT_platform_wayland EGL_KHR_platform_wayland"/' "$E"
grep -c "EGL_EXT_platform_base EGL_EXT_platform_wayland" "$E"
# eglSwapBuffersWithDamageKHR (same signature as the EXT one) must also go through libhybris' wrapper, which does
# the Wayland attach/commit; otherwise eglGetProcAddress hands out Android's function, buffers are queued but never
# presented, and the next dequeue blocks forever (Firefox WebRender).
grep -q '"eglSwapBuffersWithDamageKHR"' "$E" || \
  sed -i 's|^\tOVERRIDE_MY(eglSwapBuffersWithDamageEXT),$|&\n\t{ .name = "eglSwapBuffersWithDamageKHR", .func = (__eglMustCastToProperFunctionPointerType) _my_eglSwapBuffersWithDamageEXT }, /* archpad */|' "$E"
grep -c '"eglSwapBuffersWithDamageKHR"' "$E"
# Android 16 has no gralloc 0/1 module and no Halium libui_compat_layer.so: add an AHardwareBuffer backend.
perl /mnt/c/mpad26/MotoPadArch/scripts/libhybris-archpad-gralloc.pl "$R/root/hb/libhybris/hybris"
# Optional EGL call trace (ARCHPAD_EGL_TRACE=1), off by default.
perl /mnt/c/mpad26/MotoPadArch/scripts/libhybris-egl-trace.pl "$E"
# Firefox WebGL 1: drop context attribute 0x3483=0, which Mali rejects.
perl /mnt/c/mpad26/MotoPadArch/scripts/libhybris-ctx-attribs.pl "$E"
# Chromium (ANGLE) needs a surfaceless EGL display.
perl /mnt/c/mpad26/MotoPadArch/scripts/libhybris-surfaceless.pl "$E"
# eglGetProcAddress returns libhybris' own egl* wrappers (ANGLE loads all entry points that way).
perl /mnt/c/mpad26/MotoPadArch/scripts/libhybris-procaddr-self.pl "$E"
arch-chroot "$R" pacman -S --noconfirm --needed base-devel autoconf automake libtool pkgconf \
  wayland wayland-protocols libdrm libglvnd >/dev/null
arch-chroot "$R" env RESUME="${RESUME:-}" bash -euo pipefail -c '
cd /root/hb/libhybris/hybris
# gcc 14+ makes implicit declarations errors; the Android headers rely on strdup from <string.h>.
export CFLAGS="-O2 -D_GNU_SOURCE" CXXFLAGS="-O2 -D_GNU_SOURCE"
[ -n "$RESUME" ] || ./autogen.sh --prefix=/usr/local/hybris \
  --enable-arch=arm64 \
  --with-android-headers=/root/hb/android-headers \
  --enable-mali-quirks \
  --enable-wayland \
  --with-default-hybris-ld-library-path=/vendor/lib64:/system/lib64:/odm/lib64 \
  > /root/hb/configure.log 2>&1 || { tail -30 /root/hb/configure.log; exit 1; }
make -j"$(nproc)" CFLAGS="$CFLAGS" > /root/hb/make.log 2>&1 || { grep -E "error|Error" /root/hb/make.log | head -20; exit 1; }
make install DESTDIR=/root/hb/out > /root/hb/install.log 2>&1
'
tar -C "$R/root/hb/out" -cf /build/out/libhybris.tar .
ls -la /build/out/libhybris.tar
tar -tf /build/out/libhybris.tar | grep -E "bin/test_|lib/lib(EGL|GLESv2|hybris-common)" | head -12
rm -rf "$R/root/hb/libhybris/hybris/.libs"
