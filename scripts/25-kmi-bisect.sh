#!/bin/bash
# Finds which config change alters symbol CRCs. Compiles a few core files under stock
# config plus one change at a time, then compares with what stock modules expect.
set -uo pipefail
P=/mnt/c/mpad26/MotoPadArch
K=/build/kernel/src
O=/build/kernel/probe
export PATH=/build/kernel/clang/bin:$PATH
MK=(make -C "$K" O="$O" ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)")
OBJS="drivers/base/core.o kernel/sched/core.o mm/slab_common.o kernel/module.o"
SYMS="_dev_info kmalloc_caches module_layout"

python3 - <<'PY' > /tmp/expected.txt
import struct
data = open('/build/stock/vr/lib/modules/mtu3.ko', 'rb').read()
shoff = struct.unpack_from('<Q', data, 0x28)[0]
es, n, si = struct.unpack_from('<HHH', data, 0x3A)
hs = [struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * es) for i in range(n)]
st = hs[si][4]
for h in hs:
    if data[st + h[0]:data.index(b'\0', st + h[0])] == b'__versions':
        v = data[h[4]:h[4] + h[5]]
        for off in range(0, len(v), 64):
            print(v[off + 8:off + 64].split(b'\0')[0].decode(), hex(struct.unpack_from('<Q', v, off)[0] & 0xffffffff))
PY
echo "=== expected (stock module mtu3.ko)"
for s in $SYMS; do grep -E "^$s " /tmp/expected.txt || echo "$s not referenced"; done

probe() {
  local label=$1; shift
  mkdir -p "$O"
  grep -v '^CONFIG_UNUSED_KSYMS_WHITELIST=' "$P/kernel/stock.config" > "$O/.config"
  # A whitelist path that does not exist breaks the build, so trimming is always off here.
  "$K/scripts/config" --file "$O/.config" -d TRIM_UNUSED_KSYMS
  [ $# -eq 0 ] || "$K/scripts/config" --file "$O/.config" "$@"
  "${MK[@]}" -s olddefconfig >/dev/null 2>&1
  "${MK[@]}" -s prepare >/dev/null 2>/tmp/prep.err || { echo "[$label] prepare failed"; tail -3 /tmp/prep.err; return; }
  rm -f "$O"/drivers/base/core.o* "$O"/kernel/sched/core.o* "$O"/mm/slab_common.o* "$O"/kernel/module.o*
  "${MK[@]}" -s $OBJS >/dev/null 2>/tmp/obj.err || { echo "[$label] compile failed"; tail -3 /tmp/obj.err; return; }
  local line="[$label]"
  for s in $SYMS; do
    local v
    v=$(cat "$O"/drivers/base/core.o.symversions "$O"/kernel/sched/core.o.symversions "$O"/mm/slab_common.o.symversions "$O"/kernel/module.o.symversions 2>/dev/null \
        | grep -E "__crc_$s\b" | head -1 | grep -oE '0x[0-9a-f]+')
    local want
    want=$(grep -E "^$s " /tmp/expected.txt | cut -d' ' -f2)
    if [ -z "$v" ]; then line+=" $s=?"
    elif [ "$((v))" = "$((want))" ]; then line+=" $s=OK"
    else line+=" $s=DIFF"; fi
  done
  echo "$line"
}

probe "stock"
probe "DEVTMPFS"    -e DEVTMPFS
probe "FHANDLE"     -e FHANDLE
probe "AUTOFS"      -e AUTOFS_FS
probe "TMPFS_ACL"   -e TMPFS_POSIX_ACL
probe "VT"          -e VT
probe "noDEBUGINFO" -d DEBUG_INFO -d DEBUG_INFO_BTF
probe "noSIGPROT"   -d MODULE_SIG_PROTECT
probe "THINLTO"     -d LTO_CLANG_FULL -e LTO_CLANG_THIN
echo BISECT_DONE
