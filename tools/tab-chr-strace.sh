P=$(grep -m1 'hybris/lib/libEGL.so.1' /tmp/chr-strace.txt | cut -d' ' -f1)
grep "^$P " /tmp/chr-strace.txt | sed -n '/hybris\/lib\/libEGL.so.1/,$p' | grep -E 'write\(2|/dev/|binder|ioctl|exit|SIG|killed|vendor/lib64/(egl|libGLES|libmali)' | grep -v -E 'ENOENT' | cut -c1-230 | head -50
