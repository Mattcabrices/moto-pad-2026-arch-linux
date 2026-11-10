# Runs as root on the tablet: converts the dumped decoder frames to PNG (detile + crop) next to a software decode.
cd /tmp/vdec || exit 1
gcc -O2 -o mm21-to-nv12 /tmp/mm21-to-nv12.c || exit 1
./mm21-to-nv12 t1080-f30.raw t1080-f30.nv12 1920 1088
ffmpeg -nostdin -loglevel error -y -f rawvideo -pix_fmt nv12 -s 1920x1088 -i t1080-f30.nv12 -vf crop=1920:1080:0:0 hw-f30.png
ffmpeg -nostdin -loglevel error -y -i t1080.h264 -vf "select=eq(n\,30)" -frames:v 1 sw-f30.png
ffmpeg -nostdin -loglevel error -i hw-f30.png -i sw-f30.png -lavfi "ssim;[0][1]psnr" -f null - 2>&1 | tail -2
ffmpeg -nostdin -i hw-f30.png -i sw-f30.png -lavfi "psnr" -f null - 2>&1 | grep -E "PSNR|SSIM"
cp hw-f30.png /tmp/hw-f30.png; chmod 644 /tmp/hw-f30.png
