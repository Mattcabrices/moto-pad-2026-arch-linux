# Runs as root on the tablet: load the Wi-Fi driver with its dependencies (including the modem
# modules ccci_md_all and mddp, which only register here), then start the helpers and power on.
A=/opt/android
# Reuse pad-load-modules' dependency-aware load() without running its full lists.
eval "$(sed -n '/^d=/,/^}$/p' /usr/local/sbin/pad-load-modules)"
for mnt in dev proc sys; do mountpoint -q $A/$mnt || mount --bind /$mnt $A/$mnt; done
dmesg -C
echo "--- load wlan driver + deps"; load wlan_drv_gen4m_6835.ko; grep -E "^(wlan_drv_gen4m_6835|ccci_md_all|mddp) " /proc/modules | cut -d' ' -f1
echo "--- wmt_launcher"; pkill -f wmt_launcher; (chroot $A /vendor/bin/wmt_launcher -p /vendor/firmware/ > /tmp/wmt_launcher.log 2>&1 &); sleep 10
grep -vE "ld.config|property service" /tmp/wmt_launcher.log | tail -5
echo "--- power on"; echo 1 > /dev/wmtWifi; sleep 8
ip -br link | grep -E "wlan|p2p|ap0" || echo "no wlan interface yet"
echo "--- kernel log"; dmesg | grep -iE "wlan|wmt|conninfra|consys|patch|wifi" | grep -viE "charger|sc8960" | tail -25
