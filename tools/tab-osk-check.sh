# Runs on the tablet: what on-screen keyboards exist for Wayland, and the state of Xwayland in the GPU desktop.
pacman -Ss '^(wvkbd|squeekboard|onboard|fcitx5|maliit-keyboard|wf-osk)$' 2>/dev/null | grep -E '^[a-z]+/' | cut -c1-80
pacman -Q onboard xorg-xwayland 2>&1
L=$(pgrep -u matt -x labwc); echo "labwc env DISPLAY: $(tr '\0' '\n' < /proc/$L/environ | grep -E '^DISPLAY=')"
echo "Xwayland running: $(pgrep -a Xwayland | cut -c1-80)"
ls /tmp/.X11-unix/ 2>/dev/null
grep -n -i -E 'xwayland|osk|keyboard|onboard' /etc/xdg/labwc/rc.xml /etc/xdg/labwc/autostart 2>/dev/null | head
ls /etc/xdg/autostart | grep -i -E 'onboard|keyboard'
