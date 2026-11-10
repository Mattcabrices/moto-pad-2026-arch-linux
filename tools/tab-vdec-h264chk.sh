# Runs as root on the tablet: first 60 frames of each test clip through the shim vs software decode (PSNR), plus speed.
pkill -9 -f "c:v [a-z0-9]*_v4l2m2m"
cd /tmp/vdec || exit 1; rm -f hw.nv12 sw.nv12
gcc -O2 -Wall -Wno-array-bounds -shared -fPIC -o libmtk-v4l2-shim.so /tmp/mtk-v4l2-shim.c -ldl -lpthread || exit 1
[ -s t1080b.mp4 ] || ffmpeg -nostdin -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 10 -c:v libx264 -preset veryfast -profile:v high -bf 3 -pix_fmt yuv420p t1080b.mp4
for x in "h264_v4l2m2m t1080b.mp4" "hevc_v4l2m2m t1080.hevc.mp4" "vp9_v4l2m2m t1080.vp9.webm"; do set -- $x
  echo "== $1"
  LD_PRELOAD=/tmp/vdec/libmtk-v4l2-shim.so timeout -s KILL 40 ffmpeg -nostdin -hide_banner -loglevel error -stats -c:v $1 -i $2 -f null - 2>&1 | tr '\r' '\n' | grep frame= | tail -1
  LD_PRELOAD=/tmp/vdec/libmtk-v4l2-shim.so timeout -s KILL 40 ffmpeg -nostdin -loglevel error -c:v $1 -i $2 -frames:v 60 -fps_mode passthrough -f rawvideo -pix_fmt nv12 -y hw.nv12
  ffmpeg -nostdin -loglevel error -i $2 -frames:v 60 -fps_mode passthrough -f rawvideo -pix_fmt nv12 -y sw.nv12
  ls -l hw.nv12 sw.nv12 | awk '{printf "%s %s  ", $5, $9}'; echo
  ffmpeg -nostdin -f rawvideo -pix_fmt nv12 -s 1920x1080 -i hw.nv12 -f rawvideo -pix_fmt nv12 -s 1920x1080 -i sw.nv12 -lavfi "psnr=stats_file=psnr.log" -f null - 2>&1 | grep -o "average:[^ ]*"
  echo "frames not identical: $(grep -vc 'psnr_avg:inf' psnr.log)"
  rm -f hw.nv12 sw.nv12
done
