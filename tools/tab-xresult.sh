echo "uptime: $(cut -d' ' -f1 /proc/uptime)"; pgrep -a Xorg || echo "Xorg not running";
dmesg | grep -vE "sc8960x|get_charger_zcv|unsupported connected type|HXTP" | grep -nE -A30 "Unable to handle|Internal error" | head -60;
echo ---xorg; grep -E "\(EE\)|\(II\) modeset|Output|crtc|Backtrace|Segmentation" /tmp/xtest.log 2>/dev/null | tail -15; tail -5 /tmp/xtest.out 2>/dev/null
