sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus XDG_RUNTIME_DIR=/run/user/1000 xfce4-panel --add=pulseaudio 2>&1 | tail -1
sleep 3; echo added
