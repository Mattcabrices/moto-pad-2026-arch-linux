echo "--- wifi/bt/connectivity modules loaded:"; grep -E "^(wlan|wmt|conninfra|connfem|connadp|bt_drv|btif|gps|fm)" /proc/modules | cut -d" " -f1 | tr "
" " "; echo; echo "--- network interfaces:"; ip -br link; echo "--- rfkill:"; ls /sys/class/rfkill 2>/dev/null | tr "
" " "; echo; echo "--- wifi modules on disk:"; ls /usr/lib/modules/$(uname -r)/archpad/*/ | grep -E "wlan|wmt|conninfra|connfem|connadp" | sort -u | tr "
" " "; echo
