# Runs as root on the tablet: installs Chromium GPU compositing support (files pushed to /tmp by tools/push-crgpu.sh):
# the archpad GBM library (tools/src/archpad-gbm.c) and the chromium-gpu launcher that uses it. Needs libhybris and
# wlroots-pad builds with dma-buf import (scripts/62, scripts/66) installed and the desktop restarted.
# Undo: rm -r /usr/local/lib/archpad-gbm   (chromium-gpu then falls back to software compositing)
set -e
pacman -Q gcc >/dev/null 2>&1 || pacman -S --noconfirm --needed gcc >/dev/null
mkdir -p /usr/local/lib/archpad-gbm
gcc -O2 -Wall -fvisibility=hidden -shared -fPIC -Wl,-soname,libgbm.so.1 -I/usr/include/libdrm \
  -o /usr/local/lib/archpad-gbm/libgbm.so.1 /tmp/archpad-gbm.c -ldl -lpthread
install -m755 /tmp/chromium-gpu /usr/local/bin/chromium-gpu
ls -l /usr/local/lib/archpad-gbm/libgbm.so.1 /usr/local/bin/chromium-gpu
# YouTube without AV1 (loaded by chromium-gpu when hardware decoding is on).
mkdir -p /usr/local/share/archpad/chromium-no-av1
install -m644 /tmp/manifest.json /tmp/no-av1.js /usr/local/share/archpad/chromium-no-av1/
