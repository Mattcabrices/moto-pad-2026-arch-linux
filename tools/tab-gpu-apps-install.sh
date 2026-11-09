# Runs as root on the tablet: installs hybris-run, the session script and GPU desktop-file overrides (pushed to /tmp),
# then restarts matt's GPU desktop and checks it came back.
install -m755 /tmp/hybris-run /usr/local/bin/hybris-run
install -m755 /tmp/pad-wayland-session /usr/local/bin/pad-wayland-session
# mpv from menus/file manager: GPU rendering (hybris-run falls back to plain mpv outside the GPU desktop).
mkdir -p /usr/local/share/applications
sed 's|^Exec=mpv |Exec=hybris-run mpv |' /usr/share/applications/mpv.desktop > /usr/local/share/applications/mpv.desktop
grep -n '^Exec' /usr/local/share/applications/mpv.desktop
update-desktop-database /usr/local/share/applications 2>/dev/null
systemctl stop getty@tty1; pkill -u matt -x labwc; sleep 2; systemctl reset-failed getty@tty1; systemctl start getty@tty1
for i in $(seq 30); do sleep 1; pgrep -u matt -x xfce4-panel >/dev/null && break; done; sleep 3
L=$(pgrep -u matt -x labwc)
echo "labwc: $L panel: $(pgrep -u matt -x xfce4-panel) preload: $(tr '\0' '\n' < /proc/$L/environ | grep LD_PRELOAD)"
tail -2 /home/matt/.pad-wayland.log
