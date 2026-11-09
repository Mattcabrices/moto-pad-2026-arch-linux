#!/bin/bash
# Builds tools/src/egl-wl-probe.c (EGL-on-Wayland start-up probe) for the tablet. Out: /build/out/egl-wl-probe
set -euo pipefail
R=/build/rootfs/root
mkdir -p $R/root/gt; cp /mnt/c/mpad26/MotoPadArch/tools/src/egl-wl-probe.c $R/root/gt/
arch-chroot $R sh -c "cd /root/gt && gcc -O1 -o egl-wl-probe egl-wl-probe.c -lEGL -lwayland-client"
cp $R/root/gt/egl-wl-probe /build/out/
