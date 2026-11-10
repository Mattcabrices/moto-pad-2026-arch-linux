# Runs as root on the tablet: Chromium hardware video decoding experiment. Plays /tmp/vdec/<clip> in tools/ffv.html
# inside the GPU desktop through chromium-gpu and prints the page's playback stats and decoder log lines.
# Usage: CLIP=t1080.mp4 ENV="ARCHPAD_GBM_DEBUG=1" FLAGS="..." bash tab-crv.sh   (ENV: variables for chromium-gpu)
# (push ffv.html crv-list.tmpl crv-cpu.sh cdp.py tab-gpu-apps.sh to /tmp first)
chmod 644 /tmp/ffv.html
[ -e /dev/video-dec0 ] || ln -s video1 /dev/video-dec0
rm -f /tmp/gpu-apps-69.txt
sed -e "s|@ENV@|env ${ENV}|" -e "s|@CLIP@|${CLIP:-t1080.mp4}|" \
    -e "s|@VMODULE@|${VMODULE:-v4l2*=4,video_decoder_pipeline=4,decoder_selector=4,gpu_video_decode*=4,mojo_video_decoder*=4,gpu_mojo_media_client*=4,*frame_pool*=4,gpu_video_accelerator_factories*=4,gpu_util=2}|" \
    -e "s|@FLAGS@|${FLAGS}|" /tmp/crv-list.tmpl > /tmp/gpu-apps-69.txt
(sleep 10; bash /tmp/crv-cpu.sh > /tmp/crv.top 2>&1) &
bash /tmp/tab-gpu-apps.sh >/dev/null 2>&1
grep -E 'ffv |V4L2|v4l2|VideoDecoder|video_decoder|Decoder|decoder|gbm|GBM|Pixmap|pixmap' /tmp/crv.out | sed -E 's/^\[[^]]*\]//' | cut -c1-220 | uniq -c | head -${LINES:-80}
cat /tmp/crv.cdp /tmp/crv.top
cp /tmp/gpu-apps-out/2.png /tmp/crv-shot.png; chmod 644 /tmp/crv-shot.png /tmp/crv.out
