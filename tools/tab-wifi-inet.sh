ip route del default via 10.55.0.2 dev usb0 2>/dev/null && echo "removed PC route"
ip route | grep default
curl -sS -m 15 -o /dev/null -w "archlinuxarm.org over wlan0: HTTP %{http_code}
" --interface wlan0 http://mirror.archlinuxarm.org/
ping -c 3 -I wlan0 1.1.1.1 | tail -2
