#!/bin/bash
# Runs in WSL: copies config/android-units/ and the mount script to the tablet and installs the systemd units.
set -e
C=/mnt/c/mpad26/MotoPadArch; T=$C/tools
tar -C $C/config -cf - android-units | bash $T/pad-ssh.sh "rm -rf /tmp/android-units; tar -C /tmp -xf -"
bash $T/pad-scp.sh $T/tab-android-mount.sh
bash $T/pad-sudo.sh $T/tab-android-units-install.sh
