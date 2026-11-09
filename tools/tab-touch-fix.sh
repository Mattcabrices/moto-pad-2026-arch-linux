# Runs as root on the tablet: installs config/labwc/rc.xml (pushed to /tmp/labwc-rc.xml) and restarts the GPU desktop.
install -m644 /tmp/labwc-rc.xml /etc/xdg/labwc/rc.xml
grep -c calibrationMatrix /etc/xdg/labwc/rc.xml
systemctl stop getty@tty1; pkill -u matt -x labwc; sleep 2; systemctl reset-failed getty@tty1; systemctl start getty@tty1
for i in $(seq 40); do sleep 1; pgrep -u matt -x xfce4-panel >/dev/null && break; done
echo "labwc: $(pgrep -u matt -x labwc) panel: $(pgrep -u matt -x xfce4-panel)"
