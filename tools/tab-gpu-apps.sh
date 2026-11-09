# Runs as root on the tablet: tries real apps with GPU rendering (hybris-run) in matt's labwc desktop.
# Commands come from the newest /tmp/gpu-apps-*.txt (one per line: "<seconds> <command...>"); each gets a screenshot.
# (packages: see HANDOFF; the mirror needs pacman -Syu first)
L=$(ls -t /tmp/gpu-apps-*.txt 2>/dev/null | head -1); [ -n "$L" ] || { echo "no /tmp/gpu-apps-*.txt list"; exit 1; }; install -m644 "$L" /tmp/gpu-apps.list
rm -rf /tmp/gpu-apps-out; mkdir -p /tmp/gpu-apps-out; chmod 777 /tmp/gpu-apps-out
cat > /tmp/gpu-apps-run <<'EOR'
#!/bin/bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
n=0
while read -r secs cmd; do
  [ -n "$secs" ] || continue
  n=$((n + 1)); O=/tmp/gpu-apps-out/$n
  echo "$cmd" > $O.cmd
  hybris-run timeout -s INT $secs bash -c "$cmd" > $O.log 2>&1 &
  sleep $((secs - 2)); timeout 8 grim -s 0.5 $O.png 2>/dev/null
  wait; echo "exit $?" >> $O.log
done < /tmp/gpu-apps.list
EOR
chmod 755 /tmp/gpu-apps-run; sudo -u matt /tmp/gpu-apps-run
for c in /tmp/gpu-apps-out/*.cmd; do
  b=${c%.cmd}; echo "=== $(cat $c)"
  grep -v -E "linker configuration|libpq_cust" $b.log | grep -v '^\s*$' | head -${LINES_PER:-25} | cut -c1-170
done
