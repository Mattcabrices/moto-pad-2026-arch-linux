# Runs as root on the tablet: binder device nodes and binderfs support.
ls -la /dev/binder /dev/hwbinder /dev/vndbinder /dev/binderfs 2>&1 | head -5
grep binder /proc/filesystems
