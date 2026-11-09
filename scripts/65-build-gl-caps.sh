#!/bin/bash
# Builds tools/src/gl-caps.c (links libhybris libEGL + libGLESv2 directly, as wlroots will). Out: /build/out/gl-caps
set -euo pipefail
R=/build/rootfs/root; O=/root/hb/out/usr/local/hybris
mkdir -p $R/root/gt; cp /mnt/c/mpad26/MotoPadArch/tools/src/gl-caps.c $R/root/gt/
arch-chroot $R sh -c "cd /root/gt && gcc -O2 -Wall -o gl-caps gl-caps.c -I$O/include -L$O/lib -lhybris-common -lEGL -lGLESv2 -Wl,-rpath-link,$O/lib -Wl,-rpath,/usr/local/hybris/lib"
cp $R/root/gt/gl-caps /build/out/
