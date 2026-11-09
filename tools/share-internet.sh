#!/bin/bash
# Runs in WSL as root: shares WSL's internet connection with the tablet over the USB network.
# The tablet (10.55.0.1) routes through WSL (10.55.0.2); WSL masquerades out of eth0.
# Undo: iptables -t nat -D POSTROUTING -s 10.55.0.0/24 -o eth0 -j MASQUERADE; sysctl -w net.ipv4.ip_forward=0
set -e
pacman -S --noconfirm --needed iptables-nft >/dev/null 2>&1 || true
for i in $(ls /sys/class/net | grep -E '^(enu|usb)'); do
  ip link set "$i" up
  ip addr add 10.55.0.2/24 dev "$i" 2>/dev/null || true
done
sysctl -qw net.ipv4.ip_forward=1
iptables -t nat -C POSTROUTING -s 10.55.0.0/24 -o eth0 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 10.55.0.0/24 -o eth0 -j MASQUERADE
iptables -C FORWARD -s 10.55.0.0/24 -j ACCEPT 2>/dev/null || iptables -A FORWARD -s 10.55.0.0/24 -j ACCEPT
iptables -C FORWARD -d 10.55.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -d 10.55.0.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT
echo "WSL is forwarding for 10.55.0.0/24"
