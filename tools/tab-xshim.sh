# Runs as root on the tablet: starts Xorg for 20 s with the noplanes shim, then reports.
rm -f /tmp/xshim.log
LD_PRELOAD=/usr/local/lib/noplanes.so nohup timeout 20 Xorg :1 vt2 -keeptty -nolisten tcp -logfile /tmp/xshim.log >/tmp/xshim.out 2>&1 &
sleep 10
echo "--- Xorg running?"; pgrep -a Xorg || echo "not running"
echo "--- log"; grep -E "\(EE\)|\(WW\)|modeset\(0\): (Output|Using|Modeline|Virtual|Atomic|Kernel)|Primary|FatalError|Backtrace" /tmp/xshim.log | head -25
tail -3 /tmp/xshim.out
