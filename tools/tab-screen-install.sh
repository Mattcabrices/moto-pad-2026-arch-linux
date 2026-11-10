# Runs as root on the tablet: installs screen on/off (power button, 5-minute idle) from files pushed to /tmp by
# tools/push-screen.sh. Undo: systemctl disable --now archpad-screend; rm /etc/systemd/logind.conf.d/50-archpad-powerkey.conf
set -e
pacman -Q swayidle >/dev/null 2>&1 || pacman -S --noconfirm --needed swayidle >/dev/null
install -m755 /tmp/archpad-screend /tmp/archpad-screen /usr/local/bin/
install -m644 /tmp/archpad-screend.service /etc/systemd/system/
mkdir -p /etc/archpad /etc/systemd/logind.conf.d
[ -e /etc/archpad/screen.conf ] || install -m644 /tmp/screen.conf /etc/archpad/screen.conf
install -m644 /tmp/50-archpad-powerkey.conf /etc/systemd/logind.conf.d/
install -m644 /tmp/autostart /etc/xdg/labwc/autostart
systemctl daemon-reload
systemctl kill -s HUP systemd-logind 2>/dev/null || true
systemctl enable --now archpad-screend
systemctl restart archpad-screend
sleep 1; systemctl --no-pager -n 3 status archpad-screend | tail -3
# Start the idle timer in the running desktop too (new sessions get it from the autostart).
pkill -u matt -x swayidle || true
sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 setsid archpad-screen idle >/dev/null 2>&1 < /dev/null &
sleep 1; pgrep -u matt -a swayidle
