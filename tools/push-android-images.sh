#!/bin/bash
# Runs in WSL: copies stock .020 system/vendor EROFS images straight to the tablet (no staging
# on the PC), for the GPU port. They land in /home/matt/android-img and are moved by
# tools/tab-android-mount.sh.
SRC="/mnt/c/Edge 26/motopad-2026/recovery-diagnostics/stock-020-chain"
bash /mnt/c/mpad26/MotoPadArch/tools/pad-ssh.sh 'mkdir -p ~/android-img' || exit 1
for f in system.img vendor.img system_ext.img product.img; do
  echo "copying $f ($(du -h "$SRC/$f" | cut -f1))"
  scp -q -i /root/.ssh/archpad_ed25519 -o UserKnownHostsFile=/root/.ssh/archpad_known_hosts "$SRC/$f" matt@10.55.0.1:android-img/ || exit 1
done
bash /mnt/c/mpad26/MotoPadArch/tools/pad-ssh.sh 'ls -la ~/android-img; df -h / | tail -1'
