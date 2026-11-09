# Read-only check of the userdata partition, run on the tablet.
cat /sys/class/block/sdc73/uevent;
echo size_sectors=$(cat /sys/class/block/sdc*/sdc73/size 2>/dev/null || cat /sys/block/sdc/sdc73/size);
grep sdc73 /proc/mounts || echo not-mounted;
which nc dd sha256sum head;
