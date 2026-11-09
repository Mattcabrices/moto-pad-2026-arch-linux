#!/bin/bash
# Runs in WSL: pushes the rebuilt libhybris + wlroots-pad to the tablet and runs the GPU client test.
set -e
T=/mnt/c/mpad26/MotoPadArch/tools
bash $T/pad-scp.sh /build/out/libhybris.tar
bash $T/pad-scp.sh /build/out/wlroots-pad.tar
bash $T/pad-sudo.sh $T/tab-gpu-client-test.sh
