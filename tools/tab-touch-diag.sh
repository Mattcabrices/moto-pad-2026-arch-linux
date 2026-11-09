# Runs as root on the tablet: why touch does nothing on the GPU desktop (labwc).
echo "labwc: $(pgrep -u matt -x labwc)  Xorg: $(pgrep -x Xorg)"
grep -i -E "touch|himax|libinput|seat|input" /home/matt/.pad-wayland-labwc.log | head -20 | cut -c1-160
echo "--- input devices:"; grep -E "^N:|^H:" /proc/bus/input/devices | paste - - | cut -c1-140
echo "--- event node perms:"; ls -l /dev/input/event* | cut -c1-80
echo "--- who holds them:"; for e in /dev/input/event*; do fuser -v $e 2>&1 | tail -n +2 | sed "s|^|$e |"; done | cut -c1-120
echo "--- seat:"; loginctl seat-status seat0 2>/dev/null | head -20; loginctl list-sessions --no-legend
echo "--- labwc env: $(tr '\0' '\n' < /proc/$(pgrep -u matt -x labwc | head -1)/environ | grep -E 'WLR_|LIBSEAT' | tr '\n' ' ')"
echo "--- 4 s of raw touch events (touch the screen now):"
H=$(grep -l -i himax /sys/class/input/event*/device/name | head -1 | cut -d/ -f5)
timeout 4 cat /dev/input/$H | wc -c
