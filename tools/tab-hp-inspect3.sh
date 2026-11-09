grep -rl -iE 'Headset Volume|Lineout Volume|HP_GAIN|hpGain' /opt/android-full/vendor/etc 2>/dev/null | head
for f in $(grep -rl -iE 'Headset Volume|Lineout Volume' /opt/android-full/vendor/etc 2>/dev/null | head -3); do echo "== $f"; grep -n -iE -B2 -A2 'Headset Volume|Lineout Volume' $f | head -30; done
ls /opt/android-full/vendor/etc/audio_param 2>/dev/null | head -40
