#!/bin/bash
# Builds tools/src/ctx-probe.c (which EGL context attributes Mali accepts) for the tablet. Out: /build/out/ctx-probe
set -euo pipefail
R=/build/rootfs/root
mkdir -p $R/root/gt; cp /mnt/c/mpad26/MotoPadArch/tools/src/ctx-probe.c $R/root/gt/
arch-chroot $R sh -c "cd /root/gt && gcc -O1 -o ctx-probe ctx-probe.c -lEGL"
cp $R/root/gt/ctx-probe /build/out/
