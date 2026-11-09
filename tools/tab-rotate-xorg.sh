# Runs as root on the tablet: rotate at X server start (so XFCE lays out for landscape from the
# beginning) and transform touch to match. Replaces the login-time xrandr rotation.
cat > /etc/X11/xorg.conf.d/20-pad-landscape.conf <<'EOF'
# The panel is natively 1600x2560 portrait; run X in landscape.
Section "Monitor"
    Identifier "dsi-landscape"
    Option "Rotate" "right"
EndSection
Section "InputClass"
    Identifier "himax touch follows rotation"
    MatchProduct "himax-touchscreen"
    MatchIsTouchscreen "on"
    Option "TransformationMatrix" "0 1 0 -1 0 1 0 0 1"
EndSection
EOF
grep -q 'Monitor-DSI-1' /etc/X11/xorg.conf.d/10-pad.conf || \
  sed -i 's|    Option "Monitor-DP-1" "dp-ignored"|    Option "Monitor-DP-1" "dp-ignored"\n    Option "Monitor-DSI-1" "dsi-landscape"|' /etc/X11/xorg.conf.d/10-pad.conf
rm -f /etc/xdg/autostart/pad-rotate.desktop
grep -c "dsi-landscape" /etc/X11/xorg.conf.d/10-pad.conf
sync
systemctl restart getty@tty1
sleep 30
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority"
$U xrandr --query | grep DSI-1
pgrep -a xfce4-session >/dev/null && echo "XFCE back"
$U xwd -root -silent -out /tmp/screen.xwd; chmod 644 /tmp/screen.xwd
