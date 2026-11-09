# Runs as root on the tablet: install the Wayland session packages for the GPU port (labwc test).
ip route | head -3
for i in 1 2 3; do pacman -Sy --noconfirm --needed labwc seatd xorg-xwayland foot grim wlr-randr >/tmp/wl-install.log 2>&1 && break; sleep 5; done
tail -4 /tmp/wl-install.log
pacman -Q labwc seatd xorg-xwayland foot grim wlr-randr wlroots0.20
