#!/usr/bin/env python3
"""Draws config/logo/arch-logo.png: the Arch Linux mark and an "Arch Linux" wordmark,
centered on black, at the tablet's landscape resolution (2560x1600).

Needs only Pillow. The mark is drawn from an SVG path (24x24 units) that this script
flattens itself, so no SVG renderer is required. The wordmark uses a bold sans font:
pass --font, or the script tries DejaVu Sans Bold, Segoe UI Bold and Arial Bold.

The Arch Linux name and logo are trademarks (see config/logo/README.md).

Usage: python3 draw-arch-logo.py [-o arch-logo.png] [--font FILE] [--size 2560x1600]
"""
import argparse
import math
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ARCH_BLUE = (0x17, 0x93, 0xD1)
TEXT_LIGHT = (0xE8, 0xE8, 0xE8)

# The Arch mark (no TM sign) in a 24x24 box.
ARCH_MARK = (
    "M11.39.605C10.376 3.092 9.764 4.72 8.635 7.132c.693.734 1.543 1.589 2.923 2.554"
    "-1.484-.61-2.496-1.224-3.252-1.86C6.86 10.842 4.596 15.138 0 23.395"
    "c3.612-2.085 6.412-3.37 9.021-3.862a6.61 6.61 0 01-.171-1.547l.003-.115"
    "c.058-2.315 1.261-4.095 2.687-3.973 1.426.12 2.534 2.096 2.478 4.409"
    "a6.52 6.52 0 01-.146 1.243c2.58.505 5.352 1.787 8.914 3.844"
    "-.702-1.293-1.33-2.459-1.929-3.57-.943-.73-1.926-1.682-3.933-2.713"
    " 1.38.359 2.367.772 3.137 1.234-6.09-11.334-6.582-12.84-8.67-17.74z"
)

FONT_CANDIDATES = [
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "C:/Windows/Fonts/segoeuib.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "/usr/share/fonts/TTF/LiberationSans-Bold.ttf",
]


def tokenize(d):
    """Splits an SVG path string into commands and numbers (handles '.5.5', '-1-2', arc flags)."""
    toks = []
    i, n = 0, len(d)
    num = re.compile(r"[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
    while i < n:
        c = d[i]
        if c.isalpha():
            toks.append(c)
            i += 1
        elif c in " ,\t\r\n":
            i += 1
        else:
            m = num.match(d, i)
            if not m:
                raise ValueError("bad path near %r" % d[i:i + 10])
            toks.append(m.group())
            i = m.end()
    return toks


def arc_points(x1, y1, rx, ry, phi, large, sweep, x2, y2, steps=48):
    """SVG elliptical arc (endpoint form) to points, per the SVG 1.1 implementation notes."""
    if rx == 0 or ry == 0:
        return [(x2, y2)]
    rx, ry = abs(rx), abs(ry)
    cp, sp = math.cos(math.radians(phi)), math.sin(math.radians(phi))
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    co = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large == sweep:
        co = -co
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    pts = []
    for k in range(1, steps + 1):
        t = t1 + dt * k / steps
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cp * x - sp * y + cx, sp * x + cp * y + cy))
    return pts


def cubic(p0, p1, p2, p3, steps=48):
    out = []
    for k in range(1, steps + 1):
        t = k / steps
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return out


def path_to_polygons(d):
    """Flattens an SVG path (M/L/H/V/C/S/A/Z, absolute and relative) into polygons."""
    toks = tokenize(d)
    polys, cur = [], []
    x = y = sx = sy = 0.0
    lastc = None  # last cubic control point, for S
    i, cmd = 0, None

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    def flag():
        # Arc flags may be packed ("01-.1"): take one character at a time.
        nonlocal i
        t = toks[i]
        if len(t) > 1:  # "01" -> 0 then "1"; "1.5" -> 1 then ".5"
            toks[i] = t[1:]
            return int(t[0])
        i += 1
        return int(t)

    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]
            i += 1
        rel = cmd.islower()
        C = cmd.upper()
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if C == "M":
            if cur:
                polys.append(cur)
            x, y = num() + ox, num() + oy
            sx, sy = x, y
            cur = [(x, y)]
            cmd = "l" if rel else "L"  # implicit lineto after moveto
            lastc = None
        elif C == "L":
            x, y = num() + ox, num() + oy
            cur.append((x, y))
            lastc = None
        elif C == "H":
            x = num() + ox
            cur.append((x, y))
            lastc = None
        elif C == "V":
            y = num() + oy
            cur.append((x, y))
            lastc = None
        elif C == "C":
            c1 = (num() + ox, num() + oy)
            c2 = (num() + ox, num() + oy)
            p = (num() + ox, num() + oy)
            cur += cubic((x, y), c1, c2, p)
            lastc = c2
            x, y = p
        elif C == "S":
            c1 = (2 * x - lastc[0], 2 * y - lastc[1]) if lastc else (x, y)
            c2 = (num() + ox, num() + oy)
            p = (num() + ox, num() + oy)
            cur += cubic((x, y), c1, c2, p)
            lastc = c2
            x, y = p
        elif C == "A":
            rx, ry, phi = num(), num(), num()
            large, sweep = flag(), flag()
            p = (num() + ox, num() + oy)
            cur += arc_points(x, y, rx, ry, phi, large, sweep, p[0], p[1])
            x, y = p
            lastc = None
        elif C == "Z":
            if cur:
                polys.append(cur)
            cur = []
            x, y = sx, sy
            lastc = None
        else:
            raise ValueError("unsupported path command " + cmd)
    if cur:
        polys.append(cur)
    return polys


def find_font(path):
    for f in ([path] if path else []) + FONT_CANDIDATES:
        if f and os.path.exists(f):
            return f
    sys.exit("no bold sans font found; pass --font /path/to/font.ttf")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "arch-logo.png"))
    ap.add_argument("--font", help="TTF/OTF for the wordmark")
    ap.add_argument("--size", default="2560x1600", help="WIDTHxHEIGHT as the viewer sees it (default 2560x1600)")
    a = ap.parse_args()
    W, H = (int(v) for v in a.size.lower().split("x"))

    SS = 4  # supersampling for smooth edges
    img = Image.new("RGB", (W * SS, H * SS), (0, 0, 0))
    dr = ImageDraw.Draw(img)

    mark_h = int(H * 0.36) * SS  # mark height
    scale = mark_h / 22.8        # glyph spans y 0.605..23.395
    font = ImageFont.truetype(find_font(a.font), int(H * 0.085) * SS)
    gap = int(H * 0.06) * SS

    words = [("Arch ", TEXT_LIGHT), ("Linux", ARCH_BLUE)]
    widths = [dr.textlength(t, font=font) for t, _ in words]
    asc, desc = font.getmetrics()
    text_w = sum(widths)
    cap_top = font.getbbox("A")[1]          # offset from the text origin to the top of capitals
    text_h = font.getbbox("A")[3] - cap_top  # cap height

    group_h = mark_h + gap + text_h
    top = (H * SS - group_h) // 2

    # Mark: center horizontally on its 24-unit box.
    mx = (W * SS - 24 * scale) / 2
    my = top - 0.605 * scale
    for poly in path_to_polygons(ARCH_MARK):
        dr.polygon([(mx + px * scale, my + py * scale) for px, py in poly], fill=ARCH_BLUE)

    x = (W * SS - text_w) / 2
    ty = top + mark_h + gap - cap_top
    for (t, col), w in zip(words, widths):
        dr.text((x, ty), t, font=font, fill=col)
        x += w

    img = img.resize((W, H), Image.LANCZOS)
    img.save(a.output, optimize=True)
    print("wrote %s (%dx%d)" % (a.output, W, H))


if __name__ == "__main__":
    main()
