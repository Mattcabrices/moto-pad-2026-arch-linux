# Runs as root on the tablet: install the shim pushed to /tmp, then restart the Android services (GPU port).
install -m644 /tmp/libpropshim.so /opt/android/system/lib64/libpropshim.so
pkill -f 'allocator@'; sleep 1
bash /tmp/tab-android-sm.sh
bash /tmp/tab-android-alloc.sh
