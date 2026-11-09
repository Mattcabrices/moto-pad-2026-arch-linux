U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority"
$U xrandr --listmonitors
$U xrandr --query | head -4
$U xprop -root _NET_WORKAREA _NET_DESKTOP_GEOMETRY
nmcli -t -f DEVICE,STATE,CONNECTION dev | grep wlan0
