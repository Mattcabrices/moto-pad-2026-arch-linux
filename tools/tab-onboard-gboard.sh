# Runs as root on the tablet: Gboard-like Onboard (phone layout, suggestion bar, auto-caps).
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U gsettings set org.onboard layout '/usr/share/onboard/layouts/Phone.onboard'
$U gsettings set org.onboard theme '/usr/share/onboard/themes/Droid.theme'
$U gsettings set org.onboard.typing-assistance active-language 'en_US' 2>/dev/null
$U gsettings set org.onboard.typing-assistance.word-suggestions enabled true
$U gsettings set org.onboard.typing-assistance.word-suggestions auto-learn true
$U gsettings set org.onboard.typing-assistance.word-suggestions punctuation-assistance true
$U gsettings set org.onboard.typing-assistance auto-capitalization true
$U gsettings set org.onboard.typing-assistance auto-correction true 2>/dev/null
pkill -u matt -f /usr/bin/onboard; sleep 1
$U sh -c 'nohup onboard >/tmp/onboard.log 2>&1 &'; sleep 8
pgrep -a onboard >/dev/null && echo "onboard restarted"; grep -iE "error|warn" /tmp/onboard.log | head -3
