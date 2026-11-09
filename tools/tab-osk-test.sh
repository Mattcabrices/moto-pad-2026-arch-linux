# Runs as root on the tablet: restart the GPU desktop, check squeekboard, open a text field, screenshot.
systemctl stop getty@tty1; pkill -u matt -x labwc; sleep 2; systemctl reset-failed getty@tty1; systemctl start getty@tty1
for i in $(seq 30); do sleep 1; pgrep -u matt -x xfce4-panel >/dev/null && break; done; sleep 5
echo "squeekboard: $(pgrep -u matt -a squeekboard | cut -c1-60)"
cat > /tmp/osk-run <<'EOR'
#!/bin/bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
timeout 12 zenity --entry --text='Type here (on-screen keyboard test)' >/dev/null 2>&1 &
sleep 6; grim -s 0.5 /tmp/osk-shot.png
busctl --user get-property sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 Visible 2>&1
wait
EOR
chmod 755 /tmp/osk-run; sudo -u matt /tmp/osk-run
journalctl --user -M matt@ -n 0 >/dev/null 2>&1; grep -i squeek /home/matt/.pad-wayland-labwc.log | tail -3
