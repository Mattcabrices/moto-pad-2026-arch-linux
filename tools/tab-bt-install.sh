# Runs as root on the tablet: start the Bluetooth bridge at boot, after Wi-Fi (which brings up WMT).
cat > /usr/local/sbin/pad-bt-start <<'EOF'
#!/bin/sh
# Loads MediaTek's BT driver and hci_vhci, then runs the /dev/stpbt <-> /dev/vhci bridge.
eval "$(sed -n '/^d=/,/^}$/p' /usr/local/sbin/pad-load-modules)"
load bt_drv_connac1x.ko
grep -q '^hci_vhci ' /proc/modules || insmod /usr/lib/modules/$(uname -r)/archpad/extra/hci_vhci.ko
exec python3 /usr/local/bin/pad-bt-bridge.py
EOF
chmod 755 /usr/local/sbin/pad-bt-start
cat > /etc/systemd/system/pad-bt.service <<'EOF'
[Unit]
Description=Bluetooth bridge for MediaTek stpbt (hci0 via hci_vhci)
After=pad-wifi.service
Requires=pad-wifi.service
Before=bluetooth.service
[Service]
ExecStart=/usr/local/sbin/pad-bt-start
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable pad-bt.service bluetooth.service 2>&1 | grep -c Created
ls /etc/xdg/autostart | grep -i blueman
