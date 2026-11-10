# Runs as root on the tablet: builds tools/src/vdec-test.c (pushed to /tmp) and decodes test clips in hardware.
cd /tmp/vdec || exit 1
gcc -O2 -Wall -o vdec-test /tmp/vdec-test.c || exit 1
[ -s t1080.h264 ] || ffmpeg -nostdin -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 10 -c:v libx264 -preset veryfast -profile:v high -pix_fmt yuv420p -f h264 t1080.h264
dmesg -C
for c in t720.h264 t1080.h264; do echo "=== $c"; timeout 60 ./vdec-test $c /dev/video1 30 /tmp/vdec/${c%.h264}-f30.raw </dev/null; echo "rc=$?"; done
dmesg | grep -E "MTK_V4L2\]\[ERROR|VCP\].*(err|fail)" | sort | uniq -c | sort -rn | head -15
