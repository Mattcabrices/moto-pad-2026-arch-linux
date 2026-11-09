# Runs as root on the tablet: start XFCE through a shimmed X server on tty1 autologin.
cat > /usr/local/bin/Xpad <<'EOF'
#!/bin/sh
# X server for the Moto Pad: the real Xorg binary with the mediatek-drm workaround shim.
# startx's default wrapper (Xorg.wrap) is setuid, which would drop LD_PRELOAD.
exec env LD_PRELOAD=/usr/local/lib/noplanes.so /usr/lib/Xorg "$@"
EOF
chmod 755 /usr/local/bin/Xpad
cat > /home/matt/.bash_profile <<'EOF'
[ -f ~/.bashrc ] && . ~/.bashrc
if [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ] && [ ! -e ~/.no-x ]; then
  exec startx /usr/bin/startxfce4 -- /usr/local/bin/Xpad vt1 -keeptty > ~/.xorg-session.log 2>&1
fi
EOF
chown matt:matt /home/matt/.bash_profile
rm -f /home/matt/.no-x
sync
systemctl restart getty@tty1
sleep 15
echo "--- processes"; pgrep -a Xorg; pgrep -a xfce4-session; pgrep -a xfwm4; pgrep -a xfce4-panel
echo "--- session log"; tail -8 /home/matt/.xorg-session.log 2>/dev/null
