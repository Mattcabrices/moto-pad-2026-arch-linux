# Runs as root on the tablet: mic routing at boot and a PipeWire source for it.
install -Dm644 /tmp/90-pad-mic.conf /etc/pipewire/pipewire.conf.d/90-pad-mic.conf
grep -q pad-audio-mic /etc/systemd/system/pad-audio.service || \
  sed -i 's|^ExecStart=/usr/local/sbin/pad-audio-speaker$|ExecStart=/usr/local/sbin/pad-audio-speaker\nExecStart=/usr/local/sbin/pad-audio-mic|' /etc/systemd/system/pad-audio.service
systemctl daemon-reload
grep ExecStart= /etc/systemd/system/pad-audio.service
U="sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U systemctl --user restart pipewire pipewire-pulse wireplumber
sleep 5
$U wpctl status 2>&1 | sed -n '/Sources:/,/Filters:/p' | head -5
