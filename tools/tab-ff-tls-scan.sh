# Runs on the tablet: lists the local-exec TLS offset loads in Firefox's executable (relaxed TLSDESC pattern
# "movz xN, #0x0, lsl #16" + "movk xN, #imm") and checks that every tpidr_el0-based access is covered.
F=${1:-/usr/lib/firefox/firefox}
objdump -d --no-show-raw-insn $F > /tmp/ff.dis
echo "tpidr reads: $(grep -c 'mrs.*tpidr_el0' /tmp/ff.dis)"
# movz #0,lsl16 followed (next instruction) by movk same reg
awk '
  /movz\tx[0-9]+, #0x0, lsl #16/ { split($0, a, "\t"); split(a[3], r, ","); reg=r[1]; addr=$1; pend=1; next }
  pend && /movk\t/ { split($0, a, "\t"); split(a[3], r, ", "); if (r[1] == reg) { print addr, $1, reg, r[2] } ; pend=0; next }
  { pend=0 }' /tmp/ff.dis > /tmp/ff-tls-pairs.txt
echo "movz/movk pairs: $(wc -l < /tmp/ff-tls-pairs.txt)"
echo "--- immediates used (count imm):"; awk '{print $4}' /tmp/ff-tls-pairs.txt | sort | uniq -c
# Other TLS access forms that would not be covered: add from tpidr with immediates.
echo "--- other forms (add xN, xT, #..., lsl #12 near tpidr):"
grep -A3 'mrs.*tpidr_el0' /tmp/ff.dis | grep -c 'lsl #12'
