L=/var/log/android-helpers.log; n0=$(wc -l < $L)
for p in $(pgrep -f 'hwservicemanager|allocator@'); do kill -35 $p; done
sleep 8
tail -n +$((n0 + 1)) $L | grep -E "#[0-9]+ pc|Cmdline|backtrace" | head -40 | cut -c1-200
