# Runs as root on the tablet: make Onboard visible (docked) and keep it visible on start.
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U gsettings set org.onboard start-minimized false
$U gsettings set org.onboard.auto-show enabled false
pkill -u matt -f /usr/bin/onboard; sleep 1
$U sh -c 'nohup onboard >/tmp/onboard.log 2>&1 &'; sleep 7
$U dbus-send --type=method_call --dest=org.onboard.Onboard /org/onboard/Onboard/Keyboard org.onboard.Onboard.Keyboard.Show 2>&1
pgrep -a onboard | head -1
$U xdotool search --name Onboard 2>/dev/null | head -1 || true
