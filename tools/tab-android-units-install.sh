# Runs as root on the tablet: installs the Android-service systemd units (pushed to /tmp/android-units/) and
# switches the running hand-started services over to them. Undo: systemctl disable --now pad-android.target.
set -e
U=/tmp/android-units
install -m755 /tmp/tab-android-mount.sh /usr/local/sbin/pad-android-mount
install -m755 $U/pad-gralloc-wait /usr/local/sbin/pad-gralloc-wait
for f in pad-android-mount.service pad-android-logd.service pad-servicemanager.service pad-hwservicemanager.service \
         pad-vndservicemanager.service pad-gralloc.service pad-android.target; do install -m644 $U/$f /etc/systemd/system/$f; done
install -m644 $U/getty-tty1-android.conf /etc/systemd/system/getty@tty1.service.d/android.conf
systemctl daemon-reload
systemctl enable pad-android.target
set +e
# Hand-started copies go; the session on tty1 is restarted afterwards so labwc gets the new allocator.
pkill -f fake-logd.py; pkill -f 'graphics.allocator@4.0'; pkill -f '/system/bin/servicemanager|hwservicemanager|vndservicemanager'; sleep 2
time systemctl start pad-android.target
systemctl --no-pager --plain list-units 'pad-*' | grep -E 'android|manager|gralloc' | cut -c1-110
ls -l /dev/socket/logdw
systemctl stop getty@tty1; pkill -u matt -x labwc; sleep 2; systemctl reset-failed getty@tty1; systemctl start getty@tty1
sleep 20
echo "labwc: $(pgrep -u matt -x labwc) panel: $(pgrep -u matt -x xfce4-panel) Xorg: $(pgrep -x Xorg) flag: $(ls /home/matt/.pad-wayland 2>&1)"
tail -2 /home/matt/.pad-wayland.log
