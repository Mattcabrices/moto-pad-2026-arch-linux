# Runs as root on the tablet: record 6 s from the built-in mics, report the level, play it back.
for c in "PGA1 Volume" "PGA2 Volume"; do amixer -q -c 0 cset name="$c" 70% 2>/dev/null; done
sleep 8
echo "recording..."
arecord -D plughw:0,10 -f S16_LE -r 48000 -c 2 -d 6 /tmp/mic.wav 2>&1 | grep -iE "error|warn" | head -2
python3 - <<'EOF'
import struct, wave, math
w = wave.open("/tmp/mic.wav"); n = w.getnframes(); d = w.readframes(n)
s = struct.unpack("<%dh" % (len(d) // 2), d)
for ch, name in ((0, "left (AIN0)"), (1, "right (AIN2)")):
    x = s[ch::2]
    rms = math.sqrt(sum(v * v for v in x) / max(1, len(x)))
    print(f"{name}: peak {max(abs(v) for v in x)}, rms {rms:.0f} (silence is near 0)")
EOF
echo "playing back..."
aplay -D plughw:0,0 /tmp/mic.wav 2>&1 | grep -iE "error" | head -2
echo done
