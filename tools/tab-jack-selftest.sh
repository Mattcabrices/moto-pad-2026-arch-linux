# Runs as root on the tablet: applies the headphone+headset-mic route by hand, reads it back, then restores speakers.
cd /usr/local/sbin
show() { for n in "HPL Mux" "HPR Mux" "Headset Volume" "LOL Mux" "Ext_Speaker_Amp Switch" "aw87xxx_profile_switch_0" "PGA_L_Mux" "Headphone Plugged In"; do printf '  %s=%s\n' "$n" "$(amixer -c 0 cget name="$n" | sed -n 's/.*: values=//p')"; done; }
python3 -c 'import importlib.machinery as m; j=m.SourceFileLoader("j","/usr/local/sbin/pad-jackd").load_module(); j.apply({2:True,4:True,6:False}, None)'
echo "headphones:"; show
python3 -c 'import importlib.machinery as m; j=m.SourceFileLoader("j","/usr/local/sbin/pad-jackd").load_module(); j.apply({2:False,4:False,6:False}, None)'
echo "speakers:"; show
