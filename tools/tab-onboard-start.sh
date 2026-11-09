U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U gsettings reset-recursively org.onboard.typing-assistance
try() { $U sh -c "nohup onboard >/tmp/onboard.log 2>&1 &"; sleep 10; if pgrep -f /usr/bin/onboard >/dev/null; then echo "OK: $1"; return 0; fi; echo "crash: $1"; return 1; }
try "Phone layout, no typing assistance" || { $U gsettings set org.onboard layout /usr/share/onboard/layouts/Compact.onboard; try "Compact layout"; }
$U gsettings get org.onboard layout
