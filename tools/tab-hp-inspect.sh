# Runs as root on the tablet: headphone paths in the stock audio_device.xml, jack state, HP mixer controls.
X=$(find /opt/android-full/vendor -name audio_device.xml 2>/dev/null | head -1)
echo "--- xml: $X"
grep -n 'path name=' "$X" | grep -iE 'head|hp|ear' | head -20
for p in headphone_output headset_output headphone_speaker_output; do
  echo "=== $p"; awk -v p="$p" '$0 ~ "<path name=\""p"\"" {f=1} f {print} f && /<\/path>/ {exit}' "$X"
done
echo "--- HP-related contents"
for n in "Headphone Plugged In" "HPL Mux" "HPR Mux" "Headset Volume" "Audio HP ImpeDance Setting"; do
  echo "# $n"; amixer -c 0 cget name="$n" 2>&1 | grep -E 'values|Item|: values' | head -4
done
pacman -Q evtest >/dev/null 2>&1 || pacman -S --noconfirm --needed evtest >/dev/null 2>&1
echo "--- jack switch state"; evtest --query /dev/input/event4 EV_SW SW_HEADPHONE_INSERT; echo "hp=$?"
evtest --query /dev/input/event4 EV_SW SW_MICROPHONE_INSERT; echo "mic=$?"
