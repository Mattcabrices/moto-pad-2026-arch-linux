# Runs as root on the tablet: tests the opt-in GPU session as matt on tty1, then switches back to Xorg/XFCE.
cat > /usr/local/pad/session-test-run <<'EOR'
#!/bin/bash
sudo -u matt touch /home/matt/.pad-wayland
systemctl stop getty@tty1; pkill -x Xorg; sleep 2
systemctl reset-failed getty@tty1; systemctl start getty@tty1
sleep 20
echo "labwc: $(pgrep -u matt -x labwc) panel: $(pgrep -u matt -x xfce4-panel) xfdesktop: $(pgrep -u matt -x xfdesktop)"
W=$(ls /run/user/1000 | grep -E '^wayland-[0-9]+$' | head -1)
sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=$W timeout 10 grim /tmp/session-shot.png && echo "screenshot ok"
cp /home/matt/.pad-wayland.log /tmp/pad-wayland.log 2>/dev/null; grep -E "ERROR|pad:|hybris" /home/matt/.pad-wayland-labwc.log | head -12
# back to the default XFCE/Xorg session
rm -f /home/matt/.pad-wayland
systemctl stop getty@tty1; pkill -u matt -x labwc; sleep 2
systemctl reset-failed getty@tty1; systemctl start getty@tty1
EOR
chmod 755 /usr/local/pad/session-test-run; rm -f /tmp/session-shot.png
systemd-run --unit=session-test --collect sh -c '/usr/local/pad/session-test-run > /tmp/session-test.log 2>&1'
for i in $(seq 40); do sleep 2; systemctl is-active -q session-test || break; done
cat /tmp/session-test.log | cut -c1-170; cat /tmp/pad-wayland.log 2>/dev/null
sleep 8; echo "--- Xorg back:"; pgrep -a Xorg | cut -c1-60
