install -Dm755 /tmp/pad-audio-mic /usr/local/sbin/pad-audio-mic
/usr/local/sbin/pad-audio-mic
arecord -l 2>/dev/null | grep -E "Capture_1 |Capture_1" | head -3
amixer -c 0 controls | cut -d"'" -f2 | grep -iE "pga.*(gain|vol)|mic.*(gain|vol)|adc.*vol|UL.*gain" | head -6
