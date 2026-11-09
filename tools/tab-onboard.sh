sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus sh -c 'nohup onboard >/tmp/onboard.log 2>&1 &'
sleep 8; pgrep -a onboard || tail -4 /tmp/onboard.log
