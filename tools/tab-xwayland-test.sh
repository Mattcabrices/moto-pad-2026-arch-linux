# Runs as root on the tablet: does an X11 app work in the GPU desktop (Xwayland via labwc)?
P=$(pgrep -u matt -x xfce4-panel)
D=$(tr '\0' '\n' < /proc/$P/environ | sed -n 's/^DISPLAY=//p')
echo "DISPLAY seen by apps: '$D'"
cat > /tmp/xw-run <<EOR
#!/bin/bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=$D
GDK_BACKEND=x11 timeout 12 zenity --info --text='X11 app via Xwayland' > /tmp/xw.log 2>&1 &
sleep 7; grim -s 0.5 /tmp/xw-shot.png
wait; echo "zenity rc=\$?"
EOR
chmod 755 /tmp/xw-run; sudo -u matt /tmp/xw-run
echo "Xwayland: $(pgrep -a Xwayland | cut -c1-100)"
tail -5 /tmp/xw.log | cut -c1-150
grep -i -E 'xwayland|xwm' /home/matt/.pad-wayland-labwc.log | tail -5 | cut -c1-150
