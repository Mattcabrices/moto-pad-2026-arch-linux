# Runs as root on the tablet: speaker routing at boot, PipeWire, and the XFCE volume plugin.
cat > /etc/systemd/system/pad-audio.service <<'EOF'
[Unit]
Description=Route audio to the Moto Pad speakers (codec line out + aw87xxx amps)
After=pad-modules.service sound.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sh -c 'for i in $(seq 30); do [ -e /dev/snd/controlC0 ] && exit 0; sleep 1; done'
ExecStart=/usr/local/sbin/pad-audio-speaker
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload; systemctl enable pad-audio.service 2>&1 | grep -c Created
pacman -S --noconfirm --needed pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol xfce4-pulseaudio-plugin 2>&1 | tail -1
U="sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>&1 | tail -1
sleep 5
$U wpctl status 2>&1 | sed -n '/Audio/,/Video/p' | head -20
