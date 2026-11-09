# Runs as root on the tablet: full upgrade (labwc/wlroots held as a precaution) + GPU test apps.
cat /tmp/upgrades.txt
pacman -Syu --noconfirm --ignore labwc,wlroots0.20 2>&1 | tail -3
pacman -S --noconfirm --needed mpv glmark2 gtk4-demos firefox 2>&1 | tail -3
pacman -Q mpv glmark2 gtk4-demos firefox labwc wlroots0.20
ls /usr/bin | grep -E "^glmark2"
