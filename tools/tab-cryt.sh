# Runs as root on the tablet: plays a YouTube video in Chromium (chromium-gpu) and reports which video decoder ran,
# the stream's codec/resolution and CPU use. Push tools/cdp.py, crv-cpu.sh and tab-gpu-apps.sh to /tmp first.
# Usage: URL=https://www.youtube.com/watch?v=... bash tab-cryt.sh
URL=${URL:-https://www.youtube.com/watch?v=YE7VzlLtp-4}
rm -f /tmp/gpu-apps-70.txt
cat > /tmp/gpu-apps-70.txt <<X
4 pkill -u matt -f /usr/lib/chromium/chromium; sleep 1; rm -rf /tmp/cr-yt; mkdir -p /tmp/cr-yt; echo ok
50 (sleep 25; python3 /tmp/cdp.py media 22) > /tmp/cryt.cdp 2>&1 & chromium-gpu --user-data-dir=/tmp/cr-yt --no-first-run --no-default-browser-check --autoplay-policy=no-user-gesture-required --remote-debugging-port=9222 "$URL" > /tmp/cryt.out 2>&1
3 pkill -u matt -f /usr/lib/chromium/chromium; true
X
(sleep 32; bash /tmp/crv-cpu.sh > /tmp/cryt.top 2>&1) &
bash /tmp/tab-gpu-apps.sh >/dev/null 2>&1
grep -E "kVideoDecoderName|kIsPlatformVideoDecoder|kResolution|\"codec\"|kFrameRate" /tmp/cryt.cdp | cut -c1-200 | sort | uniq -c
grep -E "media-error" /tmp/cryt.cdp | head -3 | cut -c1-200
echo "GPU crashes: $(grep -c 'GPU process exited' /tmp/cryt.out)"
cat /tmp/cryt.top
cp /tmp/gpu-apps-out/2.png /tmp/cryt-shot.png; chmod 644 /tmp/cryt-shot.png
