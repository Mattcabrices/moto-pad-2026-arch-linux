# Runs as root on the tablet: squeekboard (Wayland on-screen keyboard) for the GPU desktop.
pacman -S --noconfirm --needed squeekboard 2>&1 | tail -1
pacman -Q squeekboard
install -m644 /tmp/autostart /etc/xdg/labwc/autostart
cat /etc/xdg/labwc/autostart
# squeekboard follows this GNOME a11y setting (already on for Onboard); make sure for matt.
sudo -u matt env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gsettings get org.gnome.desktop.a11y.applications screen-keyboard-enabled
# Landscape keyboard at 70 % height (about a third of the screen instead of half).
sudo -u matt env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gsettings set sm.puri.Squeekboard scale-in-horizontal-screen-orientation 0.7
