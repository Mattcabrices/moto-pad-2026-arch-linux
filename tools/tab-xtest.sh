# Runs as root on the tablet (Arch). Starts Xorg briefly with panic-on-oops disabled, so a
# display-driver oops kills Xorg but leaves the kernel running to report the full trace.
sysctl -w kernel.panic_on_oops=0
cat /proc/sys/kernel/panic_on_oops
dmesg -C
rm -f /tmp/xtest.log /tmp/xtest.out
nohup timeout 20 Xorg :1 vt2 -keeptty -nolisten tcp -logfile /tmp/xtest.log >/tmp/xtest.out 2>&1 &
echo "xorg started"
