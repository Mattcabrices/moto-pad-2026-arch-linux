# Runs as root on the tablet: open a text-entry dialog and check whether Onboard slides into view.
pacman -S --noconfirm --needed zenity >/dev/null 2>&1
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
pos() { $U xwininfo -root -children | grep '"Onboard": ("onboard" "Onboard")' | grep -oE '[0-9]+x[0-9]+\+-?[0-9]+\+-?[0-9]+' | head -1; }
echo "onboard before: $(pos)"
$U sh -c 'nohup zenity --entry --title="Keyboard test" --text="Tap here and type:" >/dev/null 2>&1 &'
sleep 7
echo "onboard with text box focused: $(pos)"
$U xwd -root -silent -out /tmp/screen.xwd; chmod 644 /tmp/screen.xwd
pkill -u matt zenity; sleep 4
echo "onboard after closing: $(pos)"
