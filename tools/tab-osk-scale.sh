sudo -u matt env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gsettings set sm.puri.Squeekboard scale-in-horizontal-screen-orientation 0.7
pkill -u matt -x squeekboard; sleep 1
sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus setsid squeekboard >/dev/null 2>&1 < /dev/null &
sleep 3
sudo -u matt /tmp/osk-run
