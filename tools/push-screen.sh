#!/bin/bash
# Runs in WSL: pushes and installs screen on/off (see tools/tab-screen-install.sh).
set -e
T=/mnt/c/mpad26/MotoPadArch
for f in config/screen/archpad-screend config/screen/archpad-screen config/screen/archpad-screend.service \
         config/screen/screen.conf config/screen/50-archpad-powerkey.conf config/labwc/autostart; do
  bash $T/tools/pad-ssh.sh "rm -f /tmp/$(basename $f)"   # /tmp is sticky: replace, don't overwrite
  bash $T/tools/pad-scp.sh $T/$f >/dev/null
done
bash $T/tools/pad-sudo.sh $T/tools/tab-screen-install.sh
