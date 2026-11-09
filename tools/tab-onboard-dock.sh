U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
for o in landscape portrait; do $U gsettings set org.onboard.window.$o dock-expand true; done
$U gsettings set org.onboard.window.portrait dock-height 700
$U gsettings set org.onboard.window.landscape dock-height 500
pkill -u matt -f /usr/bin/onboard; sleep 1; $U sh -c "nohup onboard >/tmp/onboard.log 2>&1 &"; sleep 5; pgrep -c -f /usr/bin/onboard
