#!/bin/bash
# Runs in WSL: copies local files to the tablet's /tmp over the USB network.
# Usage: pad-scp.sh file [file...]
bash /mnt/c/mpad26/MotoPadArch/tools/pad-ssh.sh true || exit 1   # brings the link up, installs the key
exec scp -i /root/.ssh/archpad_ed25519 -o UserKnownHostsFile=/root/.ssh/archpad_known_hosts "$@" matt@10.55.0.1:/tmp/
