amixer -c 0 controls | cut -d"'" -f2 | grep -iE "fs1|aw87|tfa|rt5512|smart|spk|ext_spk|Ext_Speaker|amp" | head -30
