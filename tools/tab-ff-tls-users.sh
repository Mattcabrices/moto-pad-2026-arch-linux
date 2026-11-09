# Runs on the tablet: which code in Firefox's executable touches its TLS at tp+16..+72 (the bionic GL slots are
# tp+24 and tp+32)? Local-exec TLS: mrs xN, tpidr_el0 followed by add/ldr/str with small offsets.
F=/usr/lib/firefox/firefox
command -v objdump >/dev/null || { echo "objdump missing"; exit 1; }
readelf -lW $F | grep -E 'TLS'
readelf -SW $F | grep -E '\.t(data|bss)'
echo "--- tpidr_el0 reads: $(objdump -d --no-show-raw-insn $F | grep -c 'mrs.*tpidr_el0')"
objdump -d --no-show-raw-insn $F > /tmp/ff.dis
# Show each tpidr read with the next 3 instructions and the enclosing function label.
awk '/^[0-9a-f]+ <.*>:$/ {fn=$2} /mrs.*tpidr_el0/ {c=4; print "== " fn} c>0 {print; c--}' /tmp/ff.dis | head -150
