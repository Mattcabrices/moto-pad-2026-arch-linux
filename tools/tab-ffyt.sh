# Runs as root on the tablet: plays a YouTube video in Firefox (hardware decode libraries from tab-ffv.sh) and
# reports which decoder ran (YouTube normally sends VP9/AV1, which stay in software). Push tools/ffyt-list.tmpl,
# ff-vdec-user.js, ffv-cpu.sh and tab-gpu-apps.sh to /tmp first.
rm -f /tmp/gpu-apps-67.txt /tmp/ffyt.log*; cp /tmp/ffyt-list.tmpl /tmp/gpu-apps-67.txt
(sleep 25; bash /tmp/ffv-cpu.sh > /tmp/ffv.top 2>&1) &
bash /tmp/tab-gpu-apps.sh >/dev/null 2>&1
grep -E 'redirect: (h264|hevc|frame step|send|opening)' /tmp/ffv.out | sort | uniq -c
grep -h 'RemoteDecoderChild has been initialized' /tmp/ffyt.log* | grep -o 'description: .*' | sort | uniq -c
cat /tmp/ffv.top; cp /tmp/gpu-apps-out/2.png /tmp/ffyt.png; chmod 644 /tmp/ffyt.png
