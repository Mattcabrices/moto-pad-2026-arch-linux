tail -4 /tmp/archinit.log;
d=$(ls -d /newroot/var/log/pstore/* | tail -1); echo "latest pstore: $d"; ls -la $d;
f=$(ls $d/* | head -1);
grep -nE "Unable to handle|Comm:|pc :|lr :|Call trace|Kernel panic" $f | tail -12;
n=$(grep -n "Call trace" $f | tail -1 | cut -d: -f1); [ -n "$n" ] && sed -n "$((n+1)),$((n+22))p" $f
