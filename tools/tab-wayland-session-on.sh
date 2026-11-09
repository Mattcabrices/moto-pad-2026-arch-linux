# Runs as root on the tablet: switches matt's tty1 login to the GPU desktop (labwc) and leaves it on.
# Undo: rm /home/matt/.pad-wayland, then restart getty@tty1 (or log out).
echo "allocator: $(pgrep -f 'allocator' | head -1) servicemanager: $(pgrep -x servicemanager) hwservicemanager: $(pgrep -x hwservicemanager)"
ls -l /dev/binderfs/binder /dev/binderfs/hwbinder 2>&1 | cut -c1-80
cat > /usr/local/pad/session-on-run <<'EOR'
#!/bin/bash
sudo -u matt touch /home/matt/.pad-wayland
systemctl stop getty@tty1; pkill -x Xorg; sleep 2
systemctl reset-failed getty@tty1; systemctl start getty@tty1
sleep 20
echo "labwc: $(pgrep -u matt -x labwc) panel: $(pgrep -u matt -x xfce4-panel) xfdesktop: $(pgrep -u matt -x xfdesktop) Xorg: $(pgrep -x Xorg)"
echo "flag still there: $(ls /home/matt/.pad-wayland 2>&1)"
W=$(ls /run/user/1000 | grep -E '^wayland-[0-9]+$' | head -1)
sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=$W timeout 10 grim /tmp/session-shot.png && echo "screenshot ok"
cat /home/matt/.pad-wayland.log 2>/dev/null | tail -5
grep -E "ERROR|hybris" /home/matt/.pad-wayland-labwc.log | head -8
EOR
chmod 755 /usr/local/pad/session-on-run; rm -f /tmp/session-shot.png
systemd-run --unit=session-on --collect sh -c '/usr/local/pad/session-on-run > /tmp/session-on.log 2>&1'
for i in $(seq 40); do sleep 2; systemctl is-active -q session-on || break; done
cut -c1-170 /tmp/session-on.log
