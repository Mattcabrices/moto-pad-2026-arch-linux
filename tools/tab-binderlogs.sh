ls /dev/binderfs/binder_logs/ 2>&1 | head -5
for p in $(pgrep -f "servicemanager|allocator"); do echo "pid $p $(cat /proc/$p/comm): $(grep -cE "^  (node|ref)" /dev/binderfs/binder_logs/proc/$p 2>/dev/null) nodes/refs, context $(grep -m1 context /dev/binderfs/binder_logs/proc/$p 2>/dev/null)"; done
grep -iE "allocator|gralloc|mali|IAllocator" /var/log/android-helpers.log | tail -5 | cut -c1-150
