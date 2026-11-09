# Runs as root on the tablet: route to the speakers and play a 3-second 440 Hz tone.
install -Dm755 /tmp/pad-audio-speaker /usr/local/sbin/pad-audio-speaker
/usr/local/sbin/pad-audio-speaker
echo "--- volume-like controls"
amixer -c 0 controls | cut -d"'" -f2 | grep -iE "volume|gain" | grep -iE "lol|line|dac|hp|spk|dl" | head -8
echo "--- playing tone"
timeout 8 speaker-test -D plughw:0,0 -c 2 -r 48000 -t sine -f 440 -l 1 -P 4 2>&1 | grep -E "Playback|Rate|error|Error" | head -5
echo "tone done"
