nmcli -t -f DEVICE,STATE,CONNECTION dev | head -4; ip -4 -br addr show wlan0; ip route | grep default
