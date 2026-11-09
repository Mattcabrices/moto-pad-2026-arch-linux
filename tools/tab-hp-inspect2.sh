X=/opt/android-full/vendor/etc/audio_device.xml
sed -n '1,30p;420,450p' $X
grep -n 'builtin_Mic_DualMic\|ADDA_TO_CAPTURE1' $X | head -5
for n in "aw87xxx_profile_switch_0" "LOL Mux" "Ext_Speaker_Amp Switch" "Headset_PGAL_GAIN" "Lineout Volume"; do
  echo "# $n"; amixer -c 0 cget name="$n" 2>&1 | grep -E "Item|: values" | head -8
done
amixer -c 0 controls | grep -iE 'mic|pga|adc|mux' | cut -d"'" -f2 | tr '\n' '|'; echo
grep -l -i headset /opt/android-full/vendor/etc/*.xml 2>/dev/null | head
