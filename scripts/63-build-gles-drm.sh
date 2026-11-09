#!/bin/bash
# Builds the GPU-to-screen tests (tools/src/gles-drm.c readback, gles-drm-zc.c zero-copy) in the aarch64
# rootfs against the libhybris build. Output: /build/out/gles-drm, /build/out/gles-drm-zc
set -euo pipefail
R=/build/rootfs/root
mkdir -p $R/root/gt; cp /mnt/c/mpad26/MotoPadArch/tools/src/gles-drm*.c /mnt/c/mpad26/MotoPadArch/tools/src/ahb-late.c $R/root/gt/
O=/root/hb/out/usr/local/hybris
for p in gles-drm gles-drm-zc ahb-late; do
  arch-chroot $R sh -c "cd /root/gt && gcc -O2 -Wall -o $p $p.c -I$O/include -I/usr/include/libdrm -L$O/lib -lhybris-common -lEGL -ldrm -lpthread -Wl,-rpath-link,$O/lib -Wl,-rpath,/usr/local/hybris/lib"
  cp $R/root/gt/$p /build/out/
done
ls -la /build/out/gles-drm*
