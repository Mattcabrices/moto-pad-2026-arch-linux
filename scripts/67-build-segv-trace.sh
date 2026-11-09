#!/bin/bash
# Builds tools/src/segv-trace.c (crash backtrace preload) for the tablet. Out: /build/out/segv-trace.so
set -euo pipefail
R=/build/rootfs/root
mkdir -p $R/root/gt; cp /mnt/c/mpad26/MotoPadArch/tools/src/segv-trace.c $R/root/gt/
arch-chroot $R sh -c "cd /root/gt && gcc -O1 -shared -fPIC -o segv-trace.so segv-trace.c"
cp $R/root/gt/segv-trace.so /build/out/
