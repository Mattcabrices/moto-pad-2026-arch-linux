# Runs as root on the tablet: late-AHardwareBuffer-allocation experiment (tools/src/ahb-late.c). Off-screen.
install -m755 /tmp/ahb-late /usr/local/hybris/bin/ahb-late
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:/usr/local/hybris/compat EGL_PLATFORM=null
for v in "warm 0" "warm 1" "warmremake 1"; do
  set -- $v; echo "=== FIX=$1 RB=$2"
  if [ "$2" = 1 ]; then RB=1 FIX=$1 timeout 30 /usr/local/hybris/bin/ahb-late 2>&1; else FIX=$1 timeout 30 /usr/local/hybris/bin/ahb-late 2>&1; fi | grep -vE "not found|^E |^W |^I |linker" | tail -6
  echo "rc=${PIPESTATUS[0]}"
done
