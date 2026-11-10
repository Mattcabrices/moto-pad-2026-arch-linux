#!/bin/bash
# Runs in WSL: pushes and installs hardware video decoding on the tablet (see tools/tab-vdec-install.sh).
set -e
T=/mnt/c/mpad26/MotoPadArch
for f in tools/src/mtk-v4l2-shim.c config/video/mpv config/video/70-archpad-dma-heap.rules; do
  bash $T/tools/pad-scp.sh $T/$f >/dev/null
done
bash $T/tools/pad-sudo.sh $T/tools/tab-vdec-install.sh
