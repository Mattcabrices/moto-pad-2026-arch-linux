# Runs as root on the tablet: install libhybris from /tmp/libhybris.tar and run its EGL/GLES tests
# against the Mali blobs (GPU port). Needs tab-android-mount.sh + tab-gpu-restart.sh first.
R=/opt/android-full
if [ -f /tmp/libhybris.tar ]; then
  rm -rf /usr/local/hybris; tar -C / -xf /tmp/libhybris.tar && rm -f /tmp/libhybris.tar
  # NOT in ld.so.conf: its libEGL.so.1 would replace Mesa's for Xorg (glamor) and Xorg aborts at start.
  # Hybris programs use rpath /usr/local/hybris/lib or LD_LIBRARY_PATH instead.
  rm -f /etc/ld.so.conf.d/hybris.conf; ldconfig
fi
# Android libraries use absolute /system, /vendor, ... paths; point them into the mounted tree.
for d in system vendor system_ext product apex linkerconfig odm; do
  [ -e /$d ] || [ ! -e $R/$d ] || ln -s $R/$d /$d
done
# Arch keeps a real /vendor (vendor/firmware -> /usr/lib/firmware for the MTK drivers); link the rest in.
if [ -d /vendor ] && [ ! -L /vendor ]; then
  for e in $R/vendor/*; do n=$(basename $e); [ $n = firmware ] || [ -e /vendor/$n ] || ln -s $e /vendor/$n; done
fi
# Compat names the vendor blobs need but the images lack (stable AIDL: newer versions are supersets).
C=/usr/local/hybris/compat; mkdir -p $C
ln -sfn /system/lib64/android.hardware.graphics.common-V6-ndk.so $C/android.hardware.graphics.common-V3-ndk.so
export HYBRIS_LD_LIBRARY_PATH=/vendor/lib64:/system/lib64:/odm/lib64:$C
# Properties Android's init would set; read by the archpad libhybris property hooks.
mkdir -p /usr/local/hybris/etc
printf 'hwservicemanager.ready=true
servicemanager.ready=true
' > /usr/local/hybris/etc/props
B=/usr/local/hybris/bin
L=/var/log/android-helpers.log; n0=$(wc -l < $L)
export HYBRIS_LD_DEBUG=0 LD_LIBRARY_PATH=/usr/local/hybris/lib
for t in test_egl_configs test_egl test_glesv2; do
  [ -x $B/$t ] || continue
  echo "=== $t"; EGL_PLATFORM=null timeout 20 $B/$t 2>&1 | tail -15 | cut -c1-170; echo "rc=${PIPESTATUS[0]}"
done
echo "--- android log:"; tail -n +$((n0 + 1)) $L | grep -v "linker configuration" | tail -20 | cut -c1-170
dmesg | tail -5 | cut -c1-150
