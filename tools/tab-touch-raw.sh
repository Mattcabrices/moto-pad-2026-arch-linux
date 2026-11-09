# Runs as root on the tablet: records raw touchscreen positions for 30 s (first point of each touch) and the axis ranges.
H=/dev/input/$(grep -l -i himax /sys/class/input/event*/device/name | head -1 | cut -d/ -f5)
python3 - "$H" <<'EOF'
import struct, sys, time, fcntl, array
dev = sys.argv[1]
f = open(dev, 'rb', buffering=0)
def absinfo(code):
    buf = array.array('i', [0]*6)
    fcntl.ioctl(f, 0x80184540 + code, buf)  # EVIOCGABS(code)
    return buf[1], buf[2]
print("X range", absinfo(0x35), "Y range", absinfo(0x36))
end = time.time() + 120; x = y = None; down = False
import select
while time.time() < end:
    r, _, _ = select.select([f], [], [], 0.5)
    if not r: continue
    ev = f.read(24)
    _, _, t, c, v = struct.unpack('llHHi', ev)
    if t == 3 and c == 0x35: x = v
    elif t == 3 and c == 0x36: y = v
    elif t == 1 and c == 0x14a:
        if v == 1: down = True
    elif t == 0 and down and x is not None and y is not None:
        print("touch at raw x=%d y=%d" % (x, y), flush=True); down = False
EOF
echo "panel transform: output mode $(cat /sys/class/drm/card0-DSI-1/modes | head -1)"
