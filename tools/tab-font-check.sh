sudo -u matt fc-match monospace
fc-list :spacing=mono family | sort -u | head
pacman -Q ttf-dejavu noto-fonts ttf-liberation 2>&1
sudo -u matt grep -s -i font /home/matt/.config/xfce4/terminal/terminalrc
sudo -u matt env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus xfconf-query -c xfce4-terminal -l 2>/dev/null | head
