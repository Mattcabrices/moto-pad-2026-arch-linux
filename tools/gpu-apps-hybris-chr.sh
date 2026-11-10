#!/bin/bash
# Runs in WSL: rebuild libhybris (incremental), push it and rerun the newest gpu-apps list, then the Chromium log summary.
set -e
W=/mnt/c/mpad26/MotoPadArch/tools
RESUME=1 bash /mnt/c/mpad26/MotoPadArch/scripts/62-build-libhybris.sh 2>&1 | grep -E "applied|rror|libhybris.tar" || true
L=$(ls -t $W/gpu-apps-*.txt | head -1)
bash $W/pad-scp.sh /build/out/libhybris.tar "$L"
bash $W/pad-sudo.sh $W/tab-hybris-install.sh
bash $W/pad-sudo.sh $W/tab-gpu-apps.sh 2>&1 | tail -45 || true
bash $W/pad-sudo.sh $W/tab-chr-log.sh
bash $W/pad-ssh.sh "cat /tmp/gpu-apps-out/2.png" > /mnt/c/mpad26/MotoPadArch/shots/chr-try.png
