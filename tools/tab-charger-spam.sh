# Runs as root on the tablet: finds what keeps reading the charger power_supply sysfs (kernel log spam).
echo "--- rate (lines per 10 s):"; journalctl -k --since '-10s' --no-pager -o cat | wc -l
echo "--- power_supply devices:"; ls /sys/class/power_supply
echo "--- processes with power_supply files open:"
for p in /proc/[0-9]*; do
  ls -l $p/fd 2>/dev/null | grep -q power_supply && echo "$(basename $p) $(tr '\0' ' ' < $p/cmdline | cut -c1-80)"
done
echo "--- candidate pollers:"; pgrep -a -f 'upower|power-manager|battery|batt|tlp|acpid|sensors|thermald|conky|charger' | cut -c1-90
echo "--- inotify/strace sample (who opens power_supply over 3 s):"
if command -v bpftrace >/dev/null; then echo bpftrace available; fi
if command -v strace >/dev/null; then
  for pid in $(pgrep -f 'upower|xfce4-power-manager|xfce4-panel|healthd|charger'); do
    n=$(timeout 3 strace -f -e trace=openat -p $pid 2>&1 | grep -c power_supply); echo "pid $pid ($(cat /proc/$pid/comm)): $n opens"
  done
else echo "no strace"; fi
echo "--- does the spam happen with nobody reading? kernel thread? first lines with timestamps:"
journalctl -k --since '-2s' --no-pager -o short-monotonic | head -8 | cut -c1-140
echo "--- dmesg level of those lines:"; dmesg -x 2>/dev/null | tail -4 | cut -c1-100
echo "--- printk:"; cat /proc/sys/kernel/printk
echo "--- journald conf:"; grep -v '^#' /etc/systemd/journald.conf | grep . ; ls /etc/systemd/journald.conf.d 2>/dev/null
