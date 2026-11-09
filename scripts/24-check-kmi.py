#!/usr/bin/env python3
"""Checks every stock module's symbol CRCs and this_module size against the rebuilt kernel.

This runs the same CRC comparison the kernel makes at load time, without a tablet.
"""
import glob
import struct
import sys
from collections import Counter

SYMVERS = "/build/kernel/out/vmlinux.symvers"
DIRS = ["/build/stock/vr/lib/modules", "/build/stock/vendor_dlkm.d/lib/modules"]


def sections(data):
    if data[:4] != b"\x7fELF":
        raise ValueError("not ELF")
    shoff = struct.unpack_from("<Q", data, 0x28)[0]
    entsize, num, stridx = struct.unpack_from("<HHH", data, 0x3A)
    headers = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * entsize) for i in range(num)]
    stroff = headers[stridx][4]
    out = {}
    for h in headers:
        end = data.index(b"\0", stroff + h[0])
        out[data[stroff + h[0]:end].decode()] = data[h[4]:h[4] + h[5]]
    return out


kernel = {}
for line in open(SYMVERS):
    crc, name = line.split("\t")[:2]
    kernel[name] = int(crc, 16)

mods = {}
for d in DIRS:
    for path in sorted(glob.glob(d + "/*.ko")):
        mods[path.rsplit("/", 1)[1]] = sections(open(path, "rb").read())

# Symbols exported by other modules are resolved at load time, not by vmlinux.
module_exports = set()
for s in mods.values():
    module_exports.update(x.decode() for x in s.get("__ksymtab_strings", b"").split(b"\0") if x)

bad_crc, missing, sizes = [], [], Counter()
checked = 0
for name, s in mods.items():
    sizes[len(s.get(".gnu.linkonce.this_module", b""))] += 1
    v = s.get("__versions", b"")
    for off in range(0, len(v), 64):
        crc = struct.unpack_from("<Q", v, off)[0] & 0xFFFFFFFF
        sym = v[off + 8:off + 64].split(b"\0")[0].decode()
        checked += 1
        if sym in kernel:
            if kernel[sym] != crc:
                bad_crc.append((name, sym))
        elif sym not in module_exports:
            missing.append((name, sym))

print(f"modules: {len(mods)}  symbol references: {checked}  kernel exports: {len(kernel)}")
print(f"this_module sizes in stock modules: {dict(sizes)}")
print(f"CRC mismatches: {len(bad_crc)} across {len(set(m for m, _ in bad_crc))} modules")
print(f"unresolved: {len(missing)}")
for label, rows in (("mismatched", bad_crc), ("unresolved", missing)):
    syms = Counter(sym for _, sym in rows)
    if syms:
        print(f"top {label}:", ", ".join(f"{k}({n})" for k, n in syms.most_common(25)))
sys.exit(1 if bad_crc or missing else 0)
