# Runs as root on the tablet after a fresh boot: Wi-Fi bring-up in Android's order, with
# wmt_launcher traced so we can see what it blocks on.
A=/opt/android
eval "$(sed -n '/^d=/,/^}$/p' /usr/local/sbin/pad-load-modules)"
for mnt in dev proc sys; do mountpoint -q $A/$mnt || mount --bind /$mnt $A/$mnt; done
mkdir -p $A/data/vendor $A/mnt/vendor
load connfem.ko; load wmt_drv.ko; sleep 1
echo "--- start wmt_launcher (traced) before wmt_loader"
(strace -f -tt -s 96 -o /tmp/wl.strace chroot $A /vendor/bin/wmt_launcher -p /vendor/firmware/ -o 1 >/tmp/wl.out 2>&1 &)
sleep 2
echo "--- wmt_loader"; timeout 30 chroot $A /vendor/bin/wmt_loader 2>&1 | grep -v ld.config | tail -3
sleep 12
echo "--- devices"; ls /dev/stpwmt /dev/wmtWifi 2>&1
echo "--- launcher syscalls (last 25, no noise)"
grep -vE "ld.config|mmap|mprotect|munmap|rt_sigprocmask|clock_gettime|futex.*FUTEX_WAKE" /tmp/wl.strace | tail -25 | cut -c1-170
echo "--- kernel"; journalctl -k -b --no-pager -o cat -n 400 | grep -E "WMT|HIF|STP|wlan|consys" | tail -15
