#!/bin/bash
# Runs in WSL: pushes config/web to the tablet and installs the web stack (see tools/tab-web-install.sh).
set -e
T=/mnt/c/mpad26/MotoPadArch
tar -C $T/config -czf /tmp/archpad-web.tgz --exclude=node_modules --exclude=dist web
bash $T/tools/pad-scp.sh /tmp/archpad-web.tgz >/dev/null
bash $T/tools/pad-sudo.sh $T/tools/tab-web-install.sh
