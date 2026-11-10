# Runs as root on the tablet: what hardware video decode paths exist (V4L2 nodes, MTK vcodec modules, vendor codec2).
echo "== video nodes"; ls -l /dev/video* /dev/media* /dev/vcu* /dev/vpu* /dev/Vcodec* 2>&1 | head -30
for v in /sys/class/video4linux/*; do [ -e "$v/name" ] && echo "$v: $(cat $v/name)"; done
echo "== modules"; lsmod | grep -iE "vcodec|vdec|venc|vcp|vpu|v4l2|videobuf|mtk_vcu|jpeg|mdp" 
echo "== available modules"; find /lib/modules/$(uname -r) -name '*.ko*' | grep -iE "vcodec|vdec|venc|vcp|vpu|vcu|mdp|jpeg|videobuf" | head -40
echo "== android vendor init"; A=/opt/android-full; ls $A/vendor/etc/init 2>/dev/null | grep -iE "media|c2|codec|vpud|vcp|omx" 
grep -lE "media|codec" $A/vendor/etc/init/*.rc 2>/dev/null | head; 
echo "== vendor bins"; ls $A/vendor/bin $A/vendor/bin/hw 2>/dev/null | grep -iE "media|c2|codec|vpud|vcp|omx"
echo "== vendor libs"; ls $A/vendor/lib64 | grep -iE "codec2|c2|vdec|venc|vcodec|omx|stagefright" | head -60
echo "== manifest c2"; grep -rlE "media.c2" $A/vendor/etc/vintf 2>/dev/null; grep -rhE -A3 "media.c2" $A/vendor/etc/vintf/manifest* 2>/dev/null | head -20
echo "== dmesg vcodec"; dmesg | grep -iE "vcodec|vdec|vcp" | tail -20
