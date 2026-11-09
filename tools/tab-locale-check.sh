# Runs on the tablet: LANG/LC_* as seen by labwc and the panel (what apps launched from the menu inherit).
for n in labwc xfce4-panel squeekboard; do
  P=$(pgrep -u matt -x $n | head -1)
  echo "$n: $(tr '\0' '\n' < /proc/$P/environ | grep -E '^(LANG|LC_[A-Z]+)=' | tr '\n' ' ')"
done
