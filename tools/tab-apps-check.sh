# Runs as root on the tablet: check Chromium's sandbox status and start Onboard in matt's session.
for mode in sandbox no-sandbox; do
  extra=""; [ "$mode" = no-sandbox ] && extra="--no-sandbox"
  out=$(sudo -u matt timeout 60 chromium --headless=new --disable-gpu $extra --dump-dom 'data:text/html,<p>padok</p>' 2>&1)
  echo "--- chromium $mode: $(echo "$out" | grep -c padok) page(s) rendered"
  echo "$out" | grep -viE "dbus|bus\.cc" | grep -iE "sandbox|namespace|fatal|zygote" | head -3
done
echo "--- start onboard now"
sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority sh -c 'nohup onboard >/tmp/onboard.log 2>&1 &'
sleep 8; pgrep -a onboard || tail -5 /tmp/onboard.log
