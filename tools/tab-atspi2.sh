# Runs as root on the tablet: which apps are on the AT-SPI bus, and does Onboard react to a
# focused GTK3 text field (xfce4-terminal)?
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus XDG_RUNTIME_DIR=/run/user/1000"
$U sh -c 'nohup xfce4-terminal >/dev/null 2>&1 &'; sleep 6
$U python3 - <<'EOF'
import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
d = Atspi.get_desktop(0)
print("apps on the accessibility bus:", [d.get_child_at_index(i).get_name() for i in range(d.get_child_count())])
EOF
pos() { $U xwininfo -root -children | grep '"Onboard": ("onboard" "Onboard")' | grep -oE '\+-?[0-9]+\+-?[0-9]+$' | head -1; }
echo "onboard position with terminal focused: $(pos)"
