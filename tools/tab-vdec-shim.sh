# Runs as root on the tablet: builds the MTK V4L2 shim and tries FFmpeg's h264_v4l2m2m decoder through it.
cd /tmp/vdec || exit 1
gcc -O2 -Wall -shared -fPIC -o libmtk-v4l2-shim.so /tmp/mtk-v4l2-shim.c -ldl -lpthread || exit 1
export LD_PRELOAD=/tmp/vdec/libmtk-v4l2-shim.so MTK_V4L2_SHIM_DEBUG=1
[ -s t1080.mp4 ] || ffmpeg -nostdin -loglevel error -i t1080.h264 -c copy t1080.mp4
dmesg -C
time timeout 60 ffmpeg -nostdin -hide_banner -c:v h264_v4l2m2m -i t1080.mp4 -f null - 2>&1 | grep -vE "^\s*$" | tail -25
timeout 60 ffmpeg -nostdin -loglevel error -c:v h264_v4l2m2m -i t1080.mp4 -vf "select=eq(n\,30)" -frames:v 1 -y shim-f30.png
unset LD_PRELOAD
ffmpeg -nostdin -i shim-f30.png -i sw-f30.png -lavfi psnr -f null - 2>&1 | grep PSNR
dmesg | grep "MTK_V4L2\]\[ERROR" | cut -c16- | sort | uniq -c | sort -rn | head
