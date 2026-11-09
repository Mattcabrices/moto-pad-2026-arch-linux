# Runs as root on the tablet: installs the opt-in GPU Wayland session (config/labwc/*). Does NOT enable it.
# Enable: touch /home/matt/.pad-wayland  (then log out / restart getty@tty1). Disable: rm that file.
install -m755 /tmp/pad-wayland-session /usr/local/bin/pad-wayland-session
install -D -m644 /tmp/labwc-rc.xml /etc/xdg/labwc/rc.xml
install -D -m644 /tmp/labwc-autostart /etc/xdg/labwc/autostart
P=/home/matt/.bash_profile
grep -q pad-wayland "$P" || sed -i 's|^if \[ -z "\$DISPLAY" \] && \[ "\$(tty)" = /dev/tty1 \] && \[ ! -e ~/.no-x \]; then$|if [ -z "$DISPLAY" ] \&\& [ "$(tty)" = /dev/tty1 ] \&\& [ -e ~/.pad-wayland ]; then\n  exec /usr/local/bin/pad-wayland-session  # GPU desktop (labwc), opt-in\nfi\n&|' "$P"
cat "$P"
