# Runs as root on the tablet: first Wi-Fi bring-up attempt, following the stock vendor init order.
A=/opt/android
M=/usr/lib/modules/$(uname -r)/archpad
mod() { for d in second-stage first-stage; do [ -f "$M/$d/$1" ] && { insmod "$M/$d/$1" 2>&1 | sed "s/^/  insmod $1: /"; return; }; done; echo "  $1 not found"; }
for d in dev proc sys; do mountpoint -q $A/$d && umount $A/$d; done
rm -rf $A; mkdir -p $A && tar -xf /tmp/android-rt.tar -C $A
for d in dev proc sys; do mountpoint -q $A/$d || mount --bind /$d $A/$d; done
dmesg -C
echo "--- 1. connfem + wmt_drv"; mod connfem.ko; mod wmt_drv.ko; sleep 1
ls -la /dev/stpwmt /dev/wmtdetect /dev/conninfra* 2>&1 | head -4
echo "--- 2. wmt_loader"; timeout 30 chroot $A /vendor/bin/wmt_loader 2>&1 | tail -6; echo "wmt_loader exit $?"
echo "--- 3. wifi drivers"; mod wmt_chrdev_wifi.ko; mod wlan_drv_gen4m_6835.ko; sleep 1
echo "--- 4. wmt_launcher"; (chroot $A /vendor/bin/wmt_launcher -p /vendor/firmware/ > /tmp/wmt_launcher.log 2>&1 &); sleep 8
tail -4 /tmp/wmt_launcher.log
echo "--- 5. power on"; ls -la /dev/wmtWifi 2>&1; echo 1 > /dev/wmtWifi 2>&1; sleep 6
ip -br link | grep -vE "ccmni|^lo"
echo "--- unknown symbols"; dmesg | grep -i "unknown symbol" | head -8
echo "--- kernel log"; dmesg | grep -iE "wlan|wmt|conninfra|consys|wifi|fail|error" | grep -viE "charger|sc8960" | tail -30
