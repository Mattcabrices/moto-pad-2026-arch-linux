U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority"
$U xrandr --listmonitors
ls /home/matt/.config/xfce4/xfconf/xfce-perchannel-xml/
grep -E "name=\"(DP|DSI|Resolution|Scale|Rotation|Position)" /home/matt/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml 2>/dev/null | head -12
$U xfconf-query -c xfwm4 -p /general/margin_right 2>/dev/null
$U xdpyinfo 2>/dev/null | grep dimensions
