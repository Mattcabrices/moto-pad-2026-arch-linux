# Sums CPU time of all Chromium processes (and the GPU process separately) between t=10s and t=20s of a run.
tick=$(getconf CLK_TCK)
snap() { for p in $(pgrep -u matt -f /usr/lib/chromium/chromium); do [ -r /proc/$p/stat ] && echo "$p $(awk '{print $14+$15}' /proc/$p/stat) $(tr '\0' ' ' < /proc/$p/cmdline | grep -q -- '--type=gpu-process' && echo gpu || (tr '\0' ' ' < /proc/$p/cmdline | grep -q -- '--type=renderer' && echo rend || echo other))"; done; }
sleep 10; a=$(snap); sleep 10; b=$(snap)
echo "$a" > /tmp/crv.cpu.a; echo "$b" > /tmp/crv.cpu.b
awk -v t=$tick 'NR==FNR{a[$1]=$2; next} {if(!($1 in a)) next; d=$2-a[$1]; tot+=d; c[$3]+=d} END{printf "CPU over 10 s: all Chromium %.0f%%, GPU process %.0f%%, renderers %.0f%% (100%% = one core)\n", tot/t*10, c["gpu"]/t*10, c["rend"]/t*10}' /tmp/crv.cpu.a /tmp/crv.cpu.b
