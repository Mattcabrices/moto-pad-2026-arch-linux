# Runs as root on the tablet: install /tmp/wlroots-pad.tar, restart the GPU desktop, check it and count the
# compositor's scan-out buffers (dma-buf fds held by labwc).
tar -C / -xf /tmp/wlroots-pad.tar && rm /tmp/wlroots-pad.tar && echo "wlroots-pad installed"
systemctl stop getty@tty1; pkill -u matt -x labwc; sleep 2; systemctl reset-failed getty@tty1; systemctl start getty@tty1
for i in $(seq 30); do sleep 1; pgrep -u matt -x xfce4-panel >/dev/null && break; done; sleep 6
L=$(pgrep -u matt -x labwc)
echo "labwc: $L panel: $(pgrep -u matt -x xfce4-panel) squeekboard: $(pgrep -u matt -x squeekboard)"
echo "dma-bufs held by labwc: $(ls -l /proc/$L/fd 2>/dev/null | grep -c dmabuf)"
sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 grim -s 0.5 /tmp/wlr-shot.png && echo shot
grep -E "ERROR" /home/matt/.pad-wayland-labwc.log | tail -3 | cut -c1-140
