pgrep -a onboard | head -2 || true
tail -4 /tmp/onboard.log | cut -c1-160
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority"
$U xwininfo -root -children | grep -i onboard | cut -c1-110
$U xwd -root -silent -out /tmp/screen.xwd; chmod 644 /tmp/screen.xwd
