#!/bin/bash
# Runs in WSL: copies the GPU Firefox pieces to the tablet and installs them (tools/tab-firefox-gpu-install.sh).
set -e
C=/mnt/c/mpad26/MotoPadArch; T=$C/tools
for f in $T/tab-ff-tls-scan.sh $T/ff-tls-relocate.py $C/config/firefox/firefox-hybris-update \
         $C/config/firefox/archpad-firefox-hybris.hook $C/config/firefox/firefox-gpu $C/config/firefox/archpad.cfg; do
  bash $T/pad-scp.sh $f >/dev/null
done
bash $T/pad-sudo.sh $T/tab-firefox-gpu-install.sh
