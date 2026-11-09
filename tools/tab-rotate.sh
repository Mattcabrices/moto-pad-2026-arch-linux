# Runs as root on the tablet: rotate XFCE to landscape and map the touchscreen to match.
# Usage on the tablet: ROT=right|left|normal|inverted (default right).
ROT=${ROT:-right}
U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority"
$U xrandr --output DSI-1 --rotate "$ROT" 2>&1
sleep 2
$U xinput --map-to-output "himax-touchscreen" DSI-1 2>&1
$U xrandr --query | grep -E "^DSI-1|Screen 0" | head -2
pgrep -a Xorg >/dev/null && echo "X still running"
