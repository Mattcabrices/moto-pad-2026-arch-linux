#!/bin/bash
# Runs in WSL. Waits up to 15 minutes for the tablet's early-boot console (telnet 23) or
# Arch's SSH (22) on 10.55.0.1, bringing the USB network link up whenever it appears.
pkill -f '[m]tk.py' 2>/dev/null
end=$(( $(date +%s) + 900 ))
while [ "$(date +%s)" -lt "$end" ]; do
  for i in $(ls /sys/class/net | grep -E '^(enu|usb)'); do
    ip link set "$i" up 2>/dev/null
    ip addr add 10.55.0.2/24 dev "$i" 2>/dev/null
  done
  if timeout 2 bash -c '</dev/tcp/10.55.0.1/23' 2>/dev/null; then echo "$(date +%T) CONSOLE"; exit 0; fi
  if timeout 2 bash -c '</dev/tcp/10.55.0.1/22' 2>/dev/null; then echo "$(date +%T) SSH"; exit 0; fi
  sleep 2
done
echo "$(date +%T) nothing reachable"
