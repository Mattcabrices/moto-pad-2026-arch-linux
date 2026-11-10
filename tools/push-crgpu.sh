#!/bin/bash
# Runs in WSL: pushes and installs Chromium GPU compositing support (see tools/tab-crgpu-install.sh).
set -e
T=/mnt/c/mpad26/MotoPadArch
for f in tools/src/archpad-gbm.c config/chromium/chromium-gpu config/chromium/no-av1/manifest.json \
         config/chromium/no-av1/no-av1.js; do
  bash $T/tools/pad-ssh.sh "rm -f /tmp/$(basename $f)"   # /tmp is sticky: replace, don't overwrite
  bash $T/tools/pad-scp.sh $T/$f >/dev/null
done
bash $T/tools/pad-sudo.sh $T/tools/tab-crgpu-install.sh
