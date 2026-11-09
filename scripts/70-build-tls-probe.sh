#!/bin/bash
# Builds tools/src/tls-probe.c (which TLS bytes Android GL writes) for the tablet. Out: /build/out/tls-probe
set -euo pipefail
R=/build/rootfs/root
mkdir -p $R/root/gt; cp /mnt/c/mpad26/MotoPadArch/tools/src/tls-probe.c $R/root/gt/
arch-chroot $R sh -c "cd /root/gt && gcc -O1 -o tls-probe tls-probe.c -lEGL -lGLESv2 -lpthread && readelf -lW tls-probe | grep TLS"
cp $R/root/gt/tls-probe /build/out/
