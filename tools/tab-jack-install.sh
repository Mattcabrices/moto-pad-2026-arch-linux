# Runs as root on the tablet: installs the headphone jack daemon (pushed to /tmp/pad-jackd) as pad-jack.service.
set -e
install -m755 /tmp/pad-jackd /usr/local/sbin/pad-jackd
cat > /etc/systemd/system/pad-jack.service <<'EOF'
[Unit]
Description=Moto Pad headphone jack switching (speakers <-> headphones, built-in <-> headset mic)
After=pad-audio.service
Wants=pad-audio.service
[Service]
ExecStart=/usr/local/sbin/pad-jackd
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable pad-jack.service 2>&1 | grep -c Created || true
systemctl restart pad-jack.service
sleep 2
systemctl is-active pad-jack.service
journalctl -u pad-jack.service -b --no-pager | tail -5
for n in "HPL Mux" "LOL Mux" "Ext_Speaker_Amp Switch" "PGA_L_Mux"; do printf '%s: ' "$n"; amixer -c 0 cget name="$n" | grep ': values'; done
