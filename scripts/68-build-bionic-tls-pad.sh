#!/bin/bash
# Builds tools/src/bionic-tls-pad.c (LD_PRELOAD for libhybris GPU clients). Out: /build/out/bionic-tls-pad.so
set -euo pipefail
R=/build/rootfs/root
mkdir -p $R/root/gt; cp /mnt/c/mpad26/MotoPadArch/tools/src/bionic-tls-pad.c $R/root/gt/
arch-chroot $R sh -c "cd /root/gt && gcc -O1 -shared -fPIC -o bionic-tls-pad.so bionic-tls-pad.c && readelf -lW bionic-tls-pad.so | grep TLS"
cp $R/root/gt/bionic-tls-pad.so /build/out/
