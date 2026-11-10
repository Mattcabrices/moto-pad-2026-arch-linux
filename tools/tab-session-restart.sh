# Runs as root on the tablet: restart the GPU desktop (labwc session) and check that it came back.
systemctl stop getty@tty1; pkill -u matt -x labwc; sleep 2; systemctl reset-failed getty@tty1; systemctl start getty@tty1
for i in $(seq 30); do sleep 1; pgrep -u matt -x xfce4-panel >/dev/null && break; done; sleep 6
L=$(pgrep -u matt -x labwc)
echo "labwc: $L panel: $(pgrep -u matt -x xfce4-panel) squeekboard: $(pgrep -u matt -x squeekboard)"
echo "dma-bufs held by labwc: $(ls -l /proc/$L/fd 2>/dev/null | grep -c dmabuf)"
grep -E "ERROR" /home/matt/.pad-wayland-labwc.log | tail -3 | cut -c1-140
