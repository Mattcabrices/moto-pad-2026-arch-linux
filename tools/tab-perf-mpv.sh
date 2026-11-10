# Runs as root on the tablet: profiles the running mpv (and the compositor) for 6 s.
for i in $(seq 30); do pgrep -x mpv >/dev/null && break; sleep 0.5; done; sleep 3
P=$(pgrep -n -x mpv); L=$(pgrep -n -x labwc)
perf record -F 499 -g -o /tmp/perf-mpv.data -p $P,$L -- sleep 6 >/dev/null 2>&1
perf report -f -i /tmp/perf-mpv.data --no-children --sort comm,dso --stdio 2>/dev/null | grep "%" | head -25 | cut -c1-140
echo ==; perf report -f -i /tmp/perf-mpv.data --no-children --sort comm,dso,sym --stdio -g none 2>/dev/null | grep "%" | head -40 | cut -c1-160
