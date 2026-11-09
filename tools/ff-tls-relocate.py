#!/usr/bin/env python3
"""Moto Pad (archpad): move an aarch64 executable's TLS block 64 bytes up, so Android's GL TLS slots
(tp+24 TLS_SLOT_OPENGL, tp+32 TLS_SLOT_OPENGL_API) land in padding instead of the program's variables.

aarch64 executables reach their TLS with link-time offsets from the thread pointer (local-exec; relaxed TLSDESC
becomes "movz xN, #0, lsl #16; movk xN, #off"). This script adds SHIFT to every such movk immediate and grows the
PT_TLS segment (and .tbss) by SHIFT. glibc still places the block at tp+16, so the program's variables now live
at tp+16+SHIFT.. and tp+16..tp+16+SHIFT is unused.

Usage: ff-tls-relocate.py <in-exe> <out-exe> <pairs.txt>
pairs.txt: lines "<movz-addr>: <movk-addr>: <reg>, #<imm>" from tools/tab-ff-tls-scan.sh (objdump of <in-exe>).
Refuses unless every listed instruction decodes as expected and every offset lies inside the TLS block."""
import struct, sys

SHIFT = 0x40
src, dst, pairs = sys.argv[1], sys.argv[2], sys.argv[3]
b = bytearray(open(src, 'rb').read())
assert b[:4] == b'\x7fELF' and b[4] == 2 and b[18] == 183, "not an ELF64 aarch64 file"
e_phoff, = struct.unpack_from('<Q', b, 0x20)
e_shoff, = struct.unpack_from('<Q', b, 0x28)
e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx = struct.unpack_from('<HHHHH', b, 0x36)

loads, tls = [], None
for i in range(e_phnum):
    o = e_phoff + i * e_phentsize
    p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack_from('<IIQQQQQQ', b, o)
    if p_type == 1:
        loads.append((p_vaddr, p_offset, p_filesz))
    if p_type == 7:
        tls = (o, p_memsz, p_align, p_filesz)
assert tls, "no PT_TLS segment"
tls_off, memsz, align, filesz = tls
lo = (16 + align - 1) // align * align          # glibc/ABI: block starts at tp + align_up(16, p_align)
hi = lo + memsz
print(f"PT_TLS memsz {memsz:#x} align {align:#x}: offsets tp+{lo:#x}..tp+{hi:#x}")

def file_off(va):
    for v, o, fs in loads:
        if v <= va < v + fs:
            return o + va - v
    raise SystemExit(f"address {va:#x} not in a PT_LOAD")

n = 0
for line in open(pairs):
    f = line.replace(',', ' ').split()
    if len(f) < 4:
        continue
    movz_va, movk_va, reg, imm = int(f[0].rstrip(':'), 16), int(f[1].rstrip(':'), 16), f[2], int(f[3].lstrip('#'), 16)
    rd = int(reg.lstrip('x'))
    # movz xRd, #0, lsl #16 : sf=1 opc=10 100101 hw=01 imm16=0
    z = struct.unpack_from('<I', b, file_off(movz_va))[0]
    assert z == (0xD2A00000 | rd), f"{movz_va:#x}: not movz x{rd}, #0, lsl #16 ({z:#010x})"
    o = file_off(movk_va)
    k = struct.unpack_from('<I', b, o)[0]
    assert k & 0xFFE0001F == (0xF2800000 | rd), f"{movk_va:#x}: not movk x{rd}, #imm ({k:#010x})"
    assert (k >> 5) & 0xFFFF == imm, f"{movk_va:#x}: immediate mismatch"
    assert lo <= imm < hi, f"{movk_va:#x}: offset {imm:#x} outside the TLS block"
    k = (k & ~(0xFFFF << 5)) | ((imm + SHIFT) << 5)
    struct.pack_into('<I', b, o, k)
    n += 1

struct.pack_into('<Q', b, tls_off + 40, memsz + SHIFT)          # p_memsz
# .tbss size, for tools that look at sections
shstr = e_shoff + e_shstrndx * e_shentsize
shstr_off, = struct.unpack_from('<Q', b, shstr + 0x18)
for i in range(e_shnum):
    s = e_shoff + i * e_shentsize
    name = b[shstr_off + struct.unpack_from('<I', b, s)[0]:].split(b'\0', 1)[0]
    if name == b'.tbss':
        size, = struct.unpack_from('<Q', b, s + 0x20)
        struct.pack_into('<Q', b, s + 0x20, size + SHIFT)
open(dst, 'wb').write(b)
print(f"patched {n} TLS offsets (+{SHIFT:#x}); PT_TLS memsz {memsz:#x} -> {memsz + SHIFT:#x}; wrote {dst}")
