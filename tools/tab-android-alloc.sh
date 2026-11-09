# Runs as root on the tablet: start MediaTek's gralloc allocator HAL in /opt/android-full.
R=/opt/android-full
A="env LD_PRELOAD=/data/local/libpropshim.so chroot $R"
L=/var/log/android-helpers.log; n0=$(wc -l < $L)
ls $R/vendor/bin/hw/ | grep -iE "allocator|composer|gralloc"
B=$(ls $R/vendor/bin/hw/ | grep -E "^android.hardware.graphics.allocator.*mt6835$" | head -1)
[ -n "$B" ] || B=$(ls $R/vendor/bin/hw/ | grep -E "^android.hardware.graphics.allocator" | head -1)
echo "starting $B"
pkill -f "$B"; sleep 1
($A /vendor/bin/hw/$B >/tmp/alloc.out 2>&1 &)
sleep 5
echo "--- running:"; pgrep -af allocator | cut -c1-100
echo "--- output:"; tail -5 /tmp/alloc.out | cut -c1-160
echo "--- android log:"; tail -n +$((n0 + 1)) $L | grep -v "linker configuration" | tail -14 | cut -c1-170
echo "--- registered HIDL services:"; $A /system/bin/lshal -i 2>/dev/null | grep -iE "allocator|mapper" | head -5
