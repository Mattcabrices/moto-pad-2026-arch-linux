# Runs as root on the tablet after boot: does everything come up by itself?
echo "uptime $(cut -d. -f1 /proc/uptime)s"
echo "services: $(systemctl is-active pad-wifi pad-bt bluetooth NetworkManager pad-audio | paste -sd' ')"
echo "wifi: $(nmcli -t -f DEVICE,STATE,CONNECTION dev | grep '^wlan0')"
echo "bt: $(bluetoothctl list 2>&1 | head -1)"
echo "speaker route: LOL=$(amixer -c 0 cget name='LOL Mux' | grep -oE ': values=[0-9]+') amp=$(amixer -c 0 cget name='Ext_Speaker_Amp Switch' | grep -oE ': values=[a-z]+')"
echo "pipewire sink: $(sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 wpctl status 2>/dev/null | grep -A2 Sinks | grep -oE 'Built-in[^[]*' | head -1)"
pgrep -a xfce4-session >/dev/null && echo "XFCE running"
