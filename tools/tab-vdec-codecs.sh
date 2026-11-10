# Runs as root on the tablet: H.264/HEVC/VP9 hardware decode through the shim (speed + bit-exact check vs software).
cd /tmp/vdec || exit 1
gcc -O2 -Wall -shared -fPIC -o libmtk-v4l2-shim.so /tmp/mtk-v4l2-shim.c -ldl -lpthread || exit 1
dmesg -C
for x in "h264_v4l2m2m t1080.mp4" "hevc_v4l2m2m t1080.hevc.mp4" "vp9_v4l2m2m t1080.vp9.webm"; do set -- $x
  echo "== $1"; LD_PRELOAD=/tmp/vdec/libmtk-v4l2-shim.so MTK_V4L2_SHIM_DEBUG=${DBG:-} timeout 90 ffmpeg -nostdin -hide_banner -loglevel error -stats -c:v $1 -i $2 -f null - 2>&1 | tr '\r' '\n' | grep -E "frame=|shim|rror" | tail -4
  LD_PRELOAD=/tmp/vdec/libmtk-v4l2-shim.so timeout 60 ffmpeg -nostdin -loglevel error -c:v $1 -i $2 -vf "select=eq(n\,30)" -frames:v 1 -y hw.png
  ffmpeg -nostdin -loglevel error -i $2 -vf "select=eq(n\,30)" -frames:v 1 -y sw.png
  ffmpeg -nostdin -i hw.png -i sw.png -lavfi psnr -f null - 2>&1 | grep -o "average:[^ ]*"
done
dmesg | grep "MTK_V4L2\]\[ERROR" | cut -c16- | sed 's/\[[0-9]*\]//' | sort | uniq -c | sort -rn | head -5
