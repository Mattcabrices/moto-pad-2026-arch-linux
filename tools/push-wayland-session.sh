#!/bin/bash
# Runs in WSL: copies the opt-in Wayland session files (config/labwc/) to the tablet and installs them.
set -e
C=/mnt/c/mpad26/MotoPadArch; T=$C/tools
cp $C/config/labwc/pad-wayland-session /tmp/pad-wayland-session
cp $C/config/labwc/rc.xml /tmp/labwc-rc.xml
cp $C/config/labwc/autostart /tmp/labwc-autostart
for f in pad-wayland-session labwc-rc.xml labwc-autostart; do bash $T/pad-scp.sh /tmp/$f; done
bash $T/pad-sudo.sh $T/tab-wayland-session-install.sh > /dev/null
bash $T/pad-sudo.sh $T/tab-xcheck.sh
