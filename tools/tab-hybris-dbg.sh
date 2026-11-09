export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat EGL_PLATFORM=null
cat > /tmp/fp.gdb <<'G'
run
set $f = $x29
set $i = 0
while $i < 14 && $f != 0
  printf "ret %lx\n", *(long*)($f+8)
  set $f = *(long*)$f
  set $i = $i + 1
end
info proc mappings
G
timeout 120 gdb -q -batch -x /tmp/fp.gdb --args /usr/local/hybris/bin/gles-pbuffer > /tmp/gdb.txt 2>&1
python3 - <<'PY'
import re
t=open('/tmp/gdb.txt').read()
addrs=[int(a,16) for a in re.findall(r'^ret ([0-9a-f]+)',t,re.M)]
maps=[]
for line in t.splitlines():
    p=line.split()
    if len(p)>=5 and p[0].startswith('0x'):
        try: maps.append((int(p[0],16),int(p[1],16),int(p[3],16),p[-1]))
        except: pass
for v in addrs:
    for s,e,off,n in maps:
        if s<=v<e: print(hex(v-s+off), n); break
    else: print(hex(v),'?')
PY
