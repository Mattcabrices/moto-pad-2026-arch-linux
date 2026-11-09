# Runs as root on the tablet: Wi-Fi bring-up with the property shim and fake logd.
A=/opt/android
install -m644 /tmp/libpropshim.so $A/system/lib64/libpropshim.so
eval "$(sed -n '/^d=/,/^}$/p' /usr/local/sbin/pad-load-modules)"
for mnt in dev proc sys; do mountpoint -q $A/$mnt || mount --bind /$mnt $A/$mnt; done
pgrep -f fake-logd.py >/dev/null || (nohup python3 /usr/local/bin/fake-logd.py >> /tmp/android-log.txt 2>&1 &)
sleep 1; : > /tmp/android-log.txt
pkill -f wmt_launcher; sleep 1
run() { chroot $A /system/bin/sh -c "true" 2>/dev/null; env LD_PRELOAD=/system/lib64/libpropshim.so chroot $A "$@"; }
load connfem.ko; load wmt_drv.ko
(env LD_PRELOAD=/system/lib64/libpropshim.so chroot $A /vendor/bin/wmt_launcher -p /vendor/firmware/ -o 1 >/dev/null 2>&1 &)
sleep 2
env LD_PRELOAD=/system/lib64/libpropshim.so timeout 30 chroot $A /vendor/bin/wmt_loader >/dev/null 2>&1
sleep 8
load wmt_chrdev_wifi.ko; load wlan_drv_gen4m_6835.ko; sleep 3
echo "--- power on: $(echo 1 > /dev/wmtWifi 2>&1 && echo ok)"; sleep 10
ip -br link | grep -E "wlan|p2p|ap0" || echo "no wlan interface yet"
echo "--- helper log"; grep -v "linker configuration" /tmp/android-log.txt | tail -15
echo "--- kernel"; journalctl -k -b --no-pager -o cat -n 300 | grep -E "WMT|HIF|STP|wlan|patch" | tail -14
