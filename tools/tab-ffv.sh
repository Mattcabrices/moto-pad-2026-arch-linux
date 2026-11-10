# Runs as root on the tablet: Firefox hardware video decoding test (tools/src/ff-v4l2-redirect.c).
# Plays /tmp/vdec/<clip> in tools/ffv.html inside the GPU desktop and prints the page's playback stats.
# Usage: RUNS="t1080b.mp4:1 t1080b.mp4:0 t1080b.mp4:1:3" bash tab-ffv.sh   (clip:hwdec[:seek every N s]; push
# ffv.html ffv-list.tmpl ff-vdec-user.js ffv-cpu.sh tab-gpu-apps.sh and both .c files to /tmp first)
chmod 644 /tmp/ff-vdec-user.js /tmp/ffv.html
gcc -O2 -Wall -shared -fPIC -o /tmp/libff-v4l2-redirect.so /tmp/ff-v4l2-redirect.c -ldl -lpthread || exit 1
gcc -O2 -Wall -Wno-array-bounds -shared -fPIC -o /tmp/libmtk-v4l2-shim-t.so /tmp/mtk-v4l2-shim.c -ldl -lpthread || exit 1
chmod 755 /tmp/libff-v4l2-redirect.so /tmp/libmtk-v4l2-shim-t.so
for r in ${RUNS:-t1080.mp4:1}; do
  clip=${r%%:*} hw=${r#*:}; seek=0; case $hw in *:*) seek=${hw#*:}; hw=${hw%%:*};; esac
  rm -f /tmp/gpu-apps-67.txt; sed -e "s/@HWDEC@/$hw/" -e "s/@CLIP@/$clip/" -e "s/@SEEK@/$seek/" /tmp/ffv-list.tmpl > /tmp/gpu-apps-67.txt
  (bash /tmp/ffv-cpu.sh > /tmp/ffv.top 2>&1) &
  bash /tmp/tab-gpu-apps.sh >/dev/null 2>&1
  echo "=== $clip hwdec=$hw seek every ${seek}s"
  grep -E '^ffv|redirect: (h264|hevc|flush|send|receive|opening|frame step)' /tmp/ffv.out | sed 's/^ff-v4l2-redirect: //; s/^ffv [^ ]* //' | uniq -c
  cat /tmp/ffv.top
  cp /tmp/gpu-apps-out/2.png /tmp/ffv-shot-$clip-$hw.png; chmod 644 /tmp/ffv-shot-*.png
done
