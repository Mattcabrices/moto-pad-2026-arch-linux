R=/opt/android-full
env LD_PRELOAD=/data/local/libpropshim.so chroot $R /system/bin/lshal list -i --neat 2>&1 | grep -viE "ld.so|linker configuration" | grep -iE "allocator|mapper|error|fail|graphics" | head -10
echo "---"; env LD_PRELOAD=/data/local/libpropshim.so chroot $R /system/bin/lshal list 2>&1 | grep -viE "ld.so|linker configuration" | tail -6 | cut -c1-150
