#!/bin/bash
# Runs in WSL: waits (up to ~6 min) for the tablet to come back after a reboot, then reports the GPU session state.
T=/mnt/c/mpad26/MotoPadArch/tools
sleep 60
for i in $(seq 30); do
  out=$(timeout 15 bash $T/pad-ssh.sh "cat /proc/uptime" 2>/dev/null) && [ -n "$out" ] && break
  sleep 10
done
echo "up: $out"
sleep 45
timeout 40 bash $T/pad-ssh.sh "uptime; systemd-analyze | head -1; systemctl --no-pager --plain list-units 'pad-*' | cut -c1-80; echo labwc: \$(pgrep -x labwc) panel: \$(pgrep -x xfce4-panel) Xorg: \$(pgrep -x Xorg); ls ~/.pad-wayland; tail -3 ~/.pad-wayland.log"
