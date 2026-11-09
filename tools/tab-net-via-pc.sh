# Runs as root on the tablet: use the PC (WSL at 10.55.0.2) as the internet gateway for now.
# Not persistent across reboots; Wi-Fi is the long-term route.
ip route replace default via 10.55.0.2 dev usb0
rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' > /etc/resolv.conf
ip route | head -3
getent hosts archlinuxarm.org | head -1 || echo "DNS failed"
curl -sS -m 15 -o /dev/null -w 'mirror HTTP %{http_code}\n' http://mirror.archlinuxarm.org/ || echo "no internet"
