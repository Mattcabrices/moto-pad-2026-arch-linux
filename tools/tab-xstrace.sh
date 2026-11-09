# Runs as root on the tablet. Streams kernel log plus an strace of Xorg's display calls to stdout,
# which pad-sudo.sh carries back to the PC as it happens.
dmesg -C
dmesg -w --notime 2>&1 | grep --line-buffered -vE "sc8960x|get_charger_zcv|unsupported connected type|HXTP" | sed -u 's/^/KMSG /' &
sleep 1
timeout 25 strace -f -tt -s 80 -e trace=openat,ioctl,mmap -o /dev/stdout \
  Xorg :1 vt2 -keeptty -nolisten tcp -verbose 6 -logfile /dev/null 2>&1 | sed -u 's/^/XTRACE /'
echo "XTRACE_DONE"
