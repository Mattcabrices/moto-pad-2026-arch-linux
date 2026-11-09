for c in MTK_SPK_TYPE_GET MTK_SPK_I2S_OUT_TYPE_GET MTK_SPK_I2S_IN_TYPE_GET "Ext_Speaker_Amp Switch" aw87xxx_profile_switch_0 "DAC In Mux" "LOL Mux"; do echo "== $c"; amixer -c 0 cget name="$c" 2>&1 | grep -E "items|Item #|: values" | tr "
" " "; echo; done
amixer -c 0 controls | cut -d"'" -f2 | grep -E "^ADDA_DL_CH[12] DL1_CH[12]$"
