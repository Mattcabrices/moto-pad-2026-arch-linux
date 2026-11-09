# Runs as root on the tablet: start Android's three service managers in /opt/android-full.
R=/opt/android-full
mkdir -p /var/lib/android-data/local
install -m644 /opt/android/system/lib64/libpropshim.so /var/lib/android-data/local/libpropshim.so
pgrep -f fake-logd.py >/dev/null || (python3 /usr/local/bin/fake-logd.py >> /var/log/android-helpers.log 2>&1 &)
mkdir -p /dev/socket
A="env LD_PRELOAD=/data/local/libpropshim.so chroot $R"
L=/var/log/android-helpers.log; n0=$(wc -l < $L)
pkill -f '/system/bin/servicemanager|hwservicemanager|vndservicemanager'; sleep 1
($A /system/bin/servicemanager >/tmp/sm.out 2>&1 &)
($A /system/bin/hwservicemanager >/tmp/hwsm.out 2>&1 &)
($A /vendor/bin/vndservicemanager /dev/vndbinder >/tmp/vndsm.out 2>&1 &)
sleep 4
echo "--- running:"; pgrep -af 'servicemanager' | cut -c1-80
echo "--- their output:"; tail -3 /tmp/sm.out /tmp/hwsm.out /tmp/vndsm.out 2>/dev/null | cut -c1-150
echo "--- android log:"; tail -n +$((n0 + 1)) $L | grep -v "linker configuration" | tail -15 | cut -c1-160
