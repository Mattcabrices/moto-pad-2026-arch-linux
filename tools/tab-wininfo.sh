# Runs as root on the tablet: list mapped top-level windows with geometry, and Onboard's state.
pacman -S --noconfirm --needed xorg-xwininfo xdotool >/dev/null 2>&1
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U sh -c 'nohup xfce4-appfinder >/tmp/appfinder.log 2>&1 &'; sleep 6
$U xwininfo -root -children | grep -E '"' | grep -vE '\(has no name\)' | head -20 | sed 's/^ *//' | cut -c1-120
echo "--- onboard: $(pgrep -c -f /usr/bin/onboard) running"
tail -3 /tmp/appfinder.log
