# Sums CPU time of all Firefox processes (and the RDD one separately) between t=10s and t=20s of a run.
tick=$(getconf CLK_TCK)
snap() { for p in $(pgrep -u matt -f 'firefox-hybris'); do [ -r /proc/$p/stat ] && echo "$p $(awk '{print $14+$15}' /proc/$p/stat) $(tr '\0' ' ' < /proc/$p/cmdline | grep -q -- '-contentproc.*rdd' && echo rdd || echo other)"; done; }
sleep 10; a=$(snap); sleep 10; b=$(snap)
echo "$a" > /tmp/ffv.cpu.a; echo "$b" > /tmp/ffv.cpu.b
awk -v t=$tick 'NR==FNR{a[$1]=$2; next} {d=$2-a[$1]; if(!($1 in a)) next; tot+=d; if($3=="rdd") rdd+=d} END{printf "CPU over 10 s: all Firefox %.0f%%, RDD %.0f%% (100%% = one core)\n", tot/t*10, rdd/t*10}' /tmp/ffv.cpu.a /tmp/ffv.cpu.b
