install -m644 /tmp/libpropshim.so /opt/android/system/lib64/libpropshim.so
mkdir -p /var/lib/android-data/local; install -m644 /tmp/libpropshim.so /var/lib/android-data/local/libpropshim.so
echo shim-installed
