# Runs as root on the tablet: what sound hardware does the kernel expose?
pacman -S --noconfirm --needed alsa-utils >/dev/null 2>&1
echo "--- cards"; cat /proc/asound/cards
echo "--- playback devices"; aplay -l 2>&1 | grep -E "^card" | head -30
echo "--- mixer control count: $(amixer -c 0 controls 2>/dev/null | wc -l)"
echo "--- speaker/amp related controls"
amixer -c 0 controls 2>/dev/null | grep -iE "spk|speaker|amp|aw87|fs15|tfa|rt5512|i2s|hp|headphone|dl1|ul" | cut -d"'" -f2 | head -40 | tr '\n' '|'; echo
echo "--- audio modules"; grep -oE "^(snd[^ ]*|mt6835[^ ]*|mtk-sp[^ ]*|audio[^ ]*|adsp|mtk-scp[^ ]*)" /proc/modules | tr '\n' ' '; echo
