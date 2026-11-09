"""Runs shell commands on the tablet's early-boot console (busybox telnetd, 10.55.0.1:23).

Usage: python3 padcmd.py 'command; command' [timeout_seconds]
       python3 padcmd.py @file.sh [timeout_seconds]   (lines joined with spaces; end each with ;)
Prints everything the tablet sends back. Telnet negotiation bytes are skipped.
"""
import socket
import sys
import time

cmd = sys.argv[1]
if cmd.startswith("@"):  # read commands from a file, one shell line
    cmd = " ".join(l.strip() for l in open(cmd[1:]) if l.strip() and not l.lstrip().startswith("#"))
cmd = cmd.rstrip().rstrip(";")
wait = float(sys.argv[2]) if len(sys.argv) > 2 else 8
s = socket.create_connection(("10.55.0.1", 23), timeout=5)
s.settimeout(0.3)


def drain(seconds):
    out, end = bytearray(), time.time() + seconds
    while time.time() < end:
        try:
            d = s.recv(65536)
            if not d:
                break
            out += d
        except socket.timeout:
            pass
    res, i = bytearray(), 0
    while i < len(out):  # drop telnet IAC sequences
        if out[i] == 255 and i + 2 < len(out):
            i += 3
            continue
        res.append(out[i])
        i += 1
    return res.decode(errors="replace")


drain(1.0)
marker = "__PADCMD_DONE__"
# The quotes split the marker in the echoed command line, so only real output matches it.
s.sendall((cmd + "; echo __PAD''CMD_DONE__\n").encode())
text, end = "", time.time() + wait
while time.time() < end and marker not in text:
    text += drain(0.5)
print(text.replace("; echo __PAD''CMD_DONE__", "").replace(marker, "").strip())
s.close()
