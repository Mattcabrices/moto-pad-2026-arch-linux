# Runs as root on the tablet: Onboard auto-show on text focus, then restart the XFCE session so
# the accessibility (AT-SPI) bus starts. tty1 autologin brings the session straight back.
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U gsettings set org.onboard.auto-show enabled true
$U gsettings set org.onboard start-minimized true
$U gsettings set org.gnome.desktop.interface toolkit-accessibility true
$U xfconf-query -c xfce4-session -p /general/StartAssistiveTechnologies -n -t bool -s true
sync
systemctl restart getty@tty1
sleep 25
pgrep -a xfce4-session >/dev/null && echo "XFCE back"
pgrep -af at-spi | head -2
pgrep -a onboard | head -1
