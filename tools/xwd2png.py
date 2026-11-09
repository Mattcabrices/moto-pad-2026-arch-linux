"""Converts a 32-bit ZPixmap XWD screenshot to a downscaled PNG (no extra libraries needed).
Usage: python3 xwd2png.py in.xwd out.png [scale]
"""
import struct
import sys
import zlib

src, dst = sys.argv[1], sys.argv[2]
scale = int(sys.argv[3]) if len(sys.argv) > 3 else 4
d = open(src, "rb").read()
h = struct.unpack(">25I", d[:100])
header_size, w, ht, bpl, ncolors = h[0], h[4], h[5], h[12], h[19]
off = header_size + ncolors * 12
rows = []
for y in range(0, ht, scale):
    line = d[off + y * bpl: off + y * bpl + w * 4]
    row = bytearray(b"\0")
    for x in range(0, w, scale):
        b, g, r = line[x * 4], line[x * 4 + 1], line[x * 4 + 2]
        row += bytes((r, g, b))
    rows.append(bytes(row))
ow, oh = (w + scale - 1) // scale, len(rows)


def chunk(t, b):
    return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", ow, oh, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 6)) + chunk(b"IEND", b"")
open(dst, "wb").write(png)
print(f"{w}x{ht} -> {ow}x{oh} {dst}")
