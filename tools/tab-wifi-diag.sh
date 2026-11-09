ls -la /dev/stpwmt /dev/wmtdetect /dev/wmtWifi /dev/stp* 2>&1 | head -6
echo "--- procs"; pgrep -af "wmt_|wlan_" || echo none
echo "--- launcher log"; cat /tmp/wmt_launcher.log 2>&1 | grep -v ld.config | tail -6
echo "--- dmesg tail (raw)"; dmesg | tail -25
