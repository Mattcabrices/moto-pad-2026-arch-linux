# Runs as root on the tablet: smaller docked Onboard, and refresh XFCE after rotation.
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U gsettings set org.onboard.window.landscape dock-height 260
$U gsettings set org.onboard.window.portrait dock-height 360
pkill -u matt -f /usr/bin/onboard; sleep 1
$U sh -c 'nohup onboard >/tmp/onboard.log 2>&1 &'
$U sh -c 'xfce4-panel -r >/dev/null 2>&1 &'
$U sh -c 'nohup xfdesktop --reload >/dev/null 2>&1 &'
sleep 8; echo refreshed
