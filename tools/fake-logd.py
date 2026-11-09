"""Stand-in for Android's logd on the Moto Pad: receives liblog datagrams on /dev/socket/logdw
and writes "TAG: message" lines to stdout, so Android helper programs' logs become readable.
Run as root: python3 fake-logd.py >> /var/log/android-helpers.log
"""
import os
import socket
import sys

PATH = "/dev/socket/logdw"
os.makedirs("/dev/socket", exist_ok=True)
try:
    os.unlink(PATH)
except FileNotFoundError:
    pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
s.bind(PATH)
os.chmod(PATH, 0o666)
LEVELS = "??VDIWEF"
last = None
while True:
    d = s.recv(65536)
    if len(d) < 13 or d[0] == 2:  # header is 11 bytes; log id 2 (events) is binary
        continue
    body = d[11:]
    prio = body[0]
    parts = body[1:].split(b"\0")
    tag = parts[0].decode(errors="replace")
    msg = parts[1].decode(errors="replace").rstrip() if len(parts) > 1 else ""
    line = f"{LEVELS[prio] if prio < len(LEVELS) else '?'} {tag}: {msg}"
    if line != last:  # drop repeats of polling loops
        print(line, flush=True)
    last = line
