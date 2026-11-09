# Runs as root on the tablet: make Onboard a docked, auto-showing tablet keyboard for matt.
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U gsettings set org.onboard layout '/usr/share/onboard/layouts/Compact.onboard'
$U gsettings set org.onboard theme '/usr/share/onboard/themes/Droid.theme'
$U gsettings set org.onboard show-status-icon true
$U gsettings set org.onboard start-minimized true
$U gsettings set org.onboard.window docking-enabled true
$U gsettings set org.onboard.window docking-expand true
$U gsettings set org.onboard.window docking-edge 'bottom'
$U gsettings set org.onboard.window force-to-top true
$U gsettings set org.onboard.auto-show enabled true
$U gsettings set org.onboard.keyboard touch-input 'multi'
# Auto-show needs applications to expose text fields over AT-SPI.
$U gsettings set org.gnome.desktop.interface toolkit-accessibility true 2>/dev/null
$U xfconf-query -c xfce4-session -p /general/StartAssistiveTechnologies -n -t bool -s true
echo "--force-renderer-accessibility" > /home/matt/.config/chromium-flags.conf
chown matt:matt /home/matt/.config/chromium-flags.conf
pkill -u matt -f /usr/bin/onboard; sleep 1
$U sh -c 'nohup onboard >/tmp/onboard.log 2>&1 &'; sleep 6
pgrep -a onboard >/dev/null && echo "onboard restarted with tablet settings"
$U gsettings get org.onboard layout
