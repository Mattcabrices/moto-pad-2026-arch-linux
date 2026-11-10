# Runs as root on the tablet: test clips for the mpv check (readable by matt).
cd /tmp/vdec || exit 1; chmod 755 /tmp/vdec
[ -s t1080p60.mp4 ] || ffmpeg -nostdin -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=60 -f lavfi -i sine=frequency=440 -t 15 -c:v libx264 -preset veryfast -profile:v high -b:v 12M -pix_fmt yuv420p -c:a aac -shortest t1080p60.mp4
chmod 644 *.mp4 *.webm; ls -l *.mp4
