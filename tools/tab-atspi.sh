grep -iE "atspi|at-spi|auto.?show|accessib|import" /tmp/onboard.log | head -10
ls /usr/lib/girepository-1.0/ | grep -i atspi
python3 -c "import gi; gi.require_version(\"Atspi\",\"2.0\"); from gi.repository import Atspi; print(\"Atspi OK\")" 2>&1 | tail -1
sudo -u matt env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gsettings get org.gnome.desktop.interface toolkit-accessibility
