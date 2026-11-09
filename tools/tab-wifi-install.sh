# Runs as root on the tablet: install pad-wifi as a boot service and drop the PC route.
install -Dm755 /tmp/pad-wifi-start /usr/local/sbin/pad-wifi-start
install -Dm755 /tmp/fake-logd.py /usr/local/bin/fake-logd.py
cat > /etc/systemd/system/pad-wifi.service <<'EOF'
[Unit]
Description=Bring up MediaTek Wi-Fi (Android helpers in /opt/android)
After=pad-modules.service
Before=NetworkManager.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/pad-wifi-start
TimeoutStartSec=120
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable pad-wifi.service 2>&1 | tail -1
# The temporary default route through the PC would override Wi-Fi; remove it.
ip route del default via 10.55.0.2 dev usb0 2>/dev/null && echo "removed PC route"
systemctl is-enabled pad-wifi.service
