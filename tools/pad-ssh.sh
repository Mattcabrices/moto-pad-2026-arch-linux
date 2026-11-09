#!/bin/bash
# Runs in WSL: brings up the tablet's USB network link and runs a command on the tablet over SSH.
# Usage: pad-ssh.sh 'command'
for i in $(ls /sys/class/net | grep -E '^(enu|usb)'); do
  ip link set "$i" up
  ip addr add 10.55.0.2/24 dev "$i" 2>/dev/null
done
install -d -m700 /root/.ssh
install -m600 /build/out/archpad_ed25519 /root/.ssh/archpad_ed25519
exec ssh -i /root/.ssh/archpad_ed25519 -o UserKnownHostsFile=/root/.ssh/archpad_known_hosts \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 matt@10.55.0.1 "$@"
