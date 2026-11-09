U="sudo -u matt env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
$U wpctl inspect 44 2>&1 | grep -E "api.alsa.path|api.alsa.pcm.device|node.name" | head -3
$U timeout 8 speaker-test -D default -c 2 -t sine -f 660 -l 1 -P 4 2>&1 | grep -iE "playback device|rate|error" | head -3
echo done
