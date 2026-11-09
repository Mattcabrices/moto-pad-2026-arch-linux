#!/bin/bash
# Runs in WSL while the tablet holds at the early-boot console. Streams the raw Arch ext4 image
# onto the tablet's userdata partition over the USB network, then verifies it by hash.
# This WIPES Android userdata.
set -uo pipefail
T=/mnt/c/mpad26/MotoPadArch/tools
IMG=/build/out/userdata-archpad.raw
DEV=/dev/sdc73
SIZE=$(stat -c %s "$IMG")
WANT=$(sha256sum "$IMG" | cut -d' ' -f1)
echo "$(date +%T) image $SIZE bytes, sha256 $WANT"

# Re-check on the tablet that DEV is still userdata and not mounted before writing.
cat > /tmp/tab-pre.sh <<EOF
grep -q '^PARTNAME=userdata\$' /sys/class/block/${DEV#/dev/}/uevent && echo PART_OK;
grep -q '^$DEV ' /proc/mounts && echo MOUNTED || echo NOT_MOUNTED;
(nc -l -p 9000 | dd of=$DEV bs=1M 2>/tmp/dd.log; sync; echo \$? > /tmp/dd.rc) &
sleep 1; echo LISTENING
EOF
pre=$(python3 $T/padcmd.py @/tmp/tab-pre.sh 8)
echo "$pre" | grep -E 'PART_OK|MOUNTED|LISTENING'
echo "$pre" | grep -q PART_OK || { echo "ABORT: $DEV is not userdata"; exit 2; }
echo "$pre" | grep -q NOT_MOUNTED || { echo "ABORT: $DEV is mounted"; exit 2; }
echo "$pre" | grep -q LISTENING || { echo "ABORT: listener did not start"; exit 2; }

echo "$(date +%T) streaming..."
python3 - "$IMG" <<'PY'
import socket, sys, time, os
path = sys.argv[1]; size = os.path.getsize(path)
s = socket.create_connection(("10.55.0.1", 9000), timeout=30)
sent, t0, last = 0, time.time(), 0
with open(path, "rb") as f:
    while True:
        b = f.read(1 << 20)
        if not b: break
        s.sendall(b); sent += len(b)
        if time.time() - last > 10:
            last = time.time()
            print(f"  {sent/size*100:5.1f}%  {sent/1e6/(time.time()-t0):.1f} MB/s", flush=True)
s.shutdown(socket.SHUT_WR); s.close()
print(f"  sent {sent} bytes in {time.time()-t0:.0f}s", flush=True)
PY

echo "$(date +%T) waiting for the tablet to finish writing"
for i in $(seq 1 60); do
  r=$(python3 $T/padcmd.py "cat /tmp/dd.rc 2>/dev/null; tail -2 /tmp/dd.log" 6)
  echo "$r" | grep -qE '^[0-9]+$' && break
  sleep 5
done
echo "$r" | tail -4

echo "$(date +%T) verifying (hashing $SIZE bytes on the tablet)"
GOT=$(python3 $T/padcmd.py "head -c $SIZE $DEV | sha256sum" 600 | grep -oE '^[0-9a-f]{64}' | head -1)
echo "tablet sha256 $GOT"
[ "$GOT" = "$WANT" ] && echo "VERIFIED: userdata holds the Arch image" || { echo "MISMATCH"; exit 3; }
