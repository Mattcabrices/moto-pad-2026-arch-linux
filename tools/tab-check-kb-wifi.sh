# Runs as root on the tablet: is Onboard's window on screen, and is Wi-Fi connected?
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority"
for w in $($U xprop -root _NET_CLIENT_LIST | grep -oE '0x[0-9a-f]+'); do
  n=$($U xprop -id "$w" WM_NAME 2>/dev/null | cut -d'"' -f2)
  case "$n" in *nboard*) echo "onboard window $w: $($U xprop -id $w _NET_WM_STATE 2>/dev/null | cut -d= -f2)"; $U xwininfo -id "$w" 2>/dev/null | grep -E "Absolute|Width|Height|Map State";; esac
done
nmcli -t -f DEVICE,STATE,CONNECTION dev | grep wlan0
