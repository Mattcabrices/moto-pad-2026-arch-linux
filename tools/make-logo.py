#!/usr/bin/env python3
"""Builds a MediaTek boot-logo image (the `logo_a` partition) for the Moto Pad 2026 (XT2575-4, MT6835).

Format (checked against the factory .020 logo.img and the tablet's own logo_a/logo_b):
  0x000  512-byte MTK header: magic 0x58881688, u32 payload size, name "logo",
         extended magic 0x58891689 at 0x30, header size 0x200, alignment 0x10 at 0x44
  0x200  payload: u32 count (123), u32 payload size, count x u32 frame offsets
         (relative to the payload start), then the zlib-compressed frames back to back
  after  the factory file appends a "cert1" signature block; this tool writes no signature
Frames 0-3 and many others are full-screen 1600x2560 BGRA8888 (byte order B,G,R,A; alpha 0xFF),
stored in the panel's native portrait orientation. Frame 0 is the boot logo ("hello moto"):
its picture is a 2560x1600 landscape image rotated 90 degrees clockwise. The other frames are
charging and status screens; they are copied from the stock image byte for byte.
LK checks the entry count and the frame resolution, so this tool keeps both.

Commands:
  info    STOCK                        print the header and frame table
  extract STOCK OUTDIR [--all]         save frame 0 (or every frame) as PNG, as the viewer sees it
  build   --stock STOCK IMAGE -o OUT   replace frame 0 with IMAGE and write OUT
  check   OUT [--stock STOCK]          parse OUT, verify every frame, compare unchanged frames

IMAGE is any picture as the viewer should see it in landscape. It is scaled to fit 2560x1600
(aspect kept, black bars; --fill to crop instead, --bg for the bar color) and rotated into the
panel orientation. Use --rotate to override (cw, ccw, 180, none) if a test shows it sideways.
Needs Python 3 and Pillow.
"""
import argparse
import hashlib
import os
import struct
import sys
import zlib

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip install pillow  (or pacman -S python-pillow)")

MAGIC = 0x58881688
EXT_MAGIC = 0x58891689
HDR = 512
PANEL_W, PANEL_H = 1600, 2560      # native portrait scan-out size
VIEW_W, VIEW_H = 2560, 1600        # landscape, as the boot logo is seen
BOOT_FRAMES = [0]                  # frames this tool replaces
ROTATE_TO_PANEL = {                # viewer orientation -> panel buffer
    "cw": Image.Transpose.ROTATE_270,
    "ccw": Image.Transpose.ROTATE_90,
    "180": Image.Transpose.ROTATE_180,
    "none": None,
}
ROTATE_TO_VIEW = {"cw": Image.Transpose.ROTATE_90, "ccw": Image.Transpose.ROTATE_270,
                  "180": Image.Transpose.ROTATE_180, "none": None}


class Logo:
    def __init__(self, data):
        if len(data) < HDR + 8:
            raise ValueError("file too small")
        magic, size = struct.unpack_from("<II", data, 0)
        if magic != MAGIC:
            raise ValueError("bad MTK header magic 0x%08x" % magic)
        name = data[8:40].split(b"\0")[0].decode("ascii", "replace")
        ext_magic, hdr_size = struct.unpack_from("<II", data, 0x30)
        if ext_magic == EXT_MAGIC and hdr_size != HDR:
            raise ValueError("unexpected header size %d" % hdr_size)
        self.header = bytearray(data[:HDR])
        self.name, self.size = name, size
        p = data[HDR:HDR + size]
        if len(p) != size:
            raise ValueError("payload truncated: header says %d, file has %d" % (size, len(p)))
        count, total = struct.unpack_from("<II", p, 0)
        if total != size:
            raise ValueError("table size %d != header size %d" % (total, size))
        offs = list(struct.unpack_from("<%dI" % count, p, 8))
        if offs[0] != 8 + 4 * count or offs != sorted(offs) or offs[-1] >= total:
            raise ValueError("frame offsets are not in the expected layout")
        ends = offs[1:] + [total]
        self.frames = [bytes(p[o:e]) for o, e in zip(offs, ends)]
        self.trailer = bytes(data[HDR + size:])

    def raw(self, i):
        d = zlib.decompressobj()
        out = d.decompress(self.frames[i]) + d.flush()
        if not d.eof:
            raise ValueError("frame %d: zlib stream incomplete" % i)
        if d.unused_data.strip(b"\0"):
            raise ValueError("frame %d: %d stray bytes after the zlib stream" % (i, len(d.unused_data)))
        return out

    def pack(self):
        count = len(self.frames)
        table = 8 + 4 * count
        offs, o = [], table
        for f in self.frames:
            offs.append(o)
            o += len(f)
        payload = struct.pack("<II", count, o) + struct.pack("<%dI" % count, *offs) + b"".join(self.frames)
        hdr = bytearray(self.header)
        struct.pack_into("<I", hdr, 4, len(payload))
        out = bytes(hdr) + payload
        return out + b"\0" * (-len(out) % 16)   # 16-byte alignment, like the factory unsigned image


def frame_dims(n):
    """Guesses width x height for a raw BGRA frame of n bytes."""
    px = n // 4
    if px == PANEL_W * PANEL_H:
        return PANEL_W, PANEL_H
    for w in range(int(px ** 0.5), 0, -1):  # nearest-to-square factorisation
        if px % w == 0:
            return w, px // w
    return 1, px


def to_view(raw, w, h, rotate):
    im = Image.frombuffer("RGBA", (w, h), raw, "raw", "BGRA", 0, 1).convert("RGB")
    t = ROTATE_TO_VIEW[rotate]
    return im.transpose(t) if t is not None else im


def from_view(path, rotate, fill, bg):
    src = Image.open(path)
    src = src.convert("RGBA")
    W, H = (VIEW_W, VIEW_H) if rotate in ("cw", "ccw") else (PANEL_W, PANEL_H)
    canvas = Image.new("RGBA", (W, H), bg + (255,))
    sw, sh = src.size
    s = max(W / sw, H / sh) if fill else min(W / sw, H / sh)
    nw, nh = max(1, round(sw * s)), max(1, round(sh * s))
    if (nw, nh) != (sw, sh):
        src = src.resize((nw, nh), Image.LANCZOS)
    canvas.alpha_composite(src, ((W - nw) // 2, (H - nh) // 2))
    t = ROTATE_TO_PANEL[rotate]
    panel = canvas.transpose(t) if t is not None else canvas
    assert panel.size == (PANEL_W, PANEL_H)
    r, g, b, _ = panel.split()
    opaque = Image.new("L", panel.size, 255)
    return Image.merge("RGBA", (r, g, b, opaque)).tobytes("raw", "BGRA")


def load(path):
    with open(path, "rb") as f:
        return Logo(f.read())


def cmd_info(a):
    lg = load(a.image)
    print("name=%r payload=%d frames=%d trailer=%d bytes%s" % (
        lg.name, lg.size, len(lg.frames), len(lg.trailer),
        " (cert1 signature present)" if b"cert1" in lg.trailer[:64] else ""))
    for i, f in enumerate(lg.frames):
        n = len(lg.raw(i))
        w, h = frame_dims(n)
        print("%3d  %8d -> %9d bytes  %dx%d BGRA" % (i, len(f), n, w, h))


def cmd_extract(a):
    lg = load(a.image)
    os.makedirs(a.outdir, exist_ok=True)
    for i in range(len(lg.frames)) if a.all else BOOT_FRAMES:
        raw = lg.raw(i)
        w, h = frame_dims(len(raw))
        im = to_view(raw, w, h, a.rotate if i in BOOT_FRAMES else "none")
        p = os.path.join(a.outdir, "frame%03d.png" % i)
        im.save(p)
        print("wrote", p, "%dx%d" % im.size)


def cmd_build(a):
    lg = load(a.stock)
    for i in BOOT_FRAMES:
        if len(lg.raw(i)) != PANEL_W * PANEL_H * 4:
            sys.exit("stock frame %d is not %dx%d BGRA; refusing" % (i, PANEL_W, PANEL_H))
    bg = tuple(int(a.bg.lstrip("#")[k:k + 2], 16) for k in (0, 2, 4))
    raw = from_view(a.input, a.rotate, a.fill, bg)
    comp = zlib.compress(raw, 9)
    for i in BOOT_FRAMES:
        lg.frames[i] = comp
    out = lg.pack()
    if a.pad_to:
        if len(out) > a.pad_to:
            sys.exit("image is %d bytes, larger than --pad-to %d" % (len(out), a.pad_to))
        out += b"\0" * (a.pad_to - len(out))
    if len(out) > a.max_size:
        sys.exit("image is %d bytes, larger than the logo_a partition (%d)" % (len(out), a.max_size))
    os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
    with open(a.output, "wb") as f:
        f.write(out)
    print("wrote %s: %d bytes, frame 0 %d bytes compressed, sha256 %s" % (
        a.output, len(out), len(comp), hashlib.sha256(out).hexdigest()))
    if a.preview:
        to_view(raw, PANEL_W, PANEL_H, a.rotate).save(a.preview)
        print("wrote preview", a.preview)
    return check(a.output, a.stock)


def check(path, stock=None):
    lg = load(path)
    ok = True
    sizes = []
    for i in range(len(lg.frames)):
        sizes.append(len(lg.raw(i)))   # raises on a broken stream
    print("parsed %s: %d frames, payload %d bytes, all zlib streams decode" % (path, len(lg.frames), lg.size))
    for i in BOOT_FRAMES:
        if sizes[i] != PANEL_W * PANEL_H * 4:
            print("FAIL frame %d is %d bytes, want %d" % (i, sizes[i], PANEL_W * PANEL_H * 4))
            ok = False
        a = lg.raw(i)[3::4]
        if a.count(255) != len(a):
            print("FAIL frame %d alpha is not fully opaque" % i)
            ok = False
    if stock:
        st = load(stock)
        if len(st.frames) != len(lg.frames):
            print("FAIL frame count %d != stock %d" % (len(lg.frames), len(st.frames)))
            ok = False
        else:
            same = [i for i in range(len(st.frames)) if st.frames[i] == lg.frames[i]]
            changed = [i for i in range(len(st.frames)) if i not in same]
            print("frames identical to stock: %d; changed: %s" % (len(same), changed))
            if changed != BOOT_FRAMES:
                print("FAIL unexpected changed frames")
                ok = False
            bad = [i for i in range(len(st.frames)) if len(st.raw(i)) != sizes[i]]
            if bad:
                print("FAIL decoded sizes differ from stock in frames", bad)
                ok = False
        if bytes(st.header[8:]) != bytes(lg.header[8:]):
            print("FAIL header differs from stock beyond the size field")
            ok = False
    print("CHECK OK" if ok else "CHECK FAILED")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("info"); p.add_argument("image")
    p = sub.add_parser("extract"); p.add_argument("image"); p.add_argument("outdir")
    p.add_argument("--all", action="store_true"); p.add_argument("--rotate", default="cw", choices=ROTATE_TO_PANEL)
    p = sub.add_parser("build")
    p.add_argument("input", help="source picture (PNG etc.), as seen in landscape")
    p.add_argument("--stock", required=True, help="stock logo image (a backup of logo_a, or the factory logo.img)")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--rotate", default="cw", choices=ROTATE_TO_PANEL,
                   help="how the landscape picture is turned into the portrait panel buffer (stock: cw)")
    p.add_argument("--fill", action="store_true", help="scale to cover the screen and crop, instead of fitting")
    p.add_argument("--bg", default="#000000", help="color for the bars when fitting (default black)")
    p.add_argument("--pad-to", type=int, default=0, help="pad the output with zeros to this many bytes")
    p.add_argument("--max-size", type=int, default=24641536, help="logo_a partition size (default 24641536)")
    p.add_argument("--preview", help="also save frame 0 as the viewer will see it, as PNG")
    p = sub.add_parser("check"); p.add_argument("image"); p.add_argument("--stock")
    a = ap.parse_args()
    if a.cmd == "info":
        return cmd_info(a)
    if a.cmd == "extract":
        return cmd_extract(a)
    if a.cmd == "build":
        return cmd_build(a)
    return check(a.image, a.stock)


if __name__ == "__main__":
    sys.exit(main() or 0)
