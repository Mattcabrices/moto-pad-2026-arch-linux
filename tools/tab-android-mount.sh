# Runs as root on the tablet: assemble a read-only Android 16 userspace at /opt/android-full from
# the stock EROFS images (GPU port). Idempotent. Nothing on the images is modified.
set -u
I=/opt/android-img; R=/opt/android-full
pacman -Q unzip >/dev/null 2>&1 || pacman -S --noconfirm --needed unzip >/dev/null 2>&1
mkdir -p $I $R
[ -d /home/matt/android-img ] && mv -f /home/matt/android-img/*.img $I/ 2>/dev/null && rmdir /home/matt/android-img 2>/dev/null
# Images and APEX payloads are EROFS or ext4; let mount detect the type.
mnt() { mountpoint -q "$2" || mount -o loop,ro "$1" "$2" 2>/dev/null || echo "mount failed: $1 -> $2"; }
mnt $I/system.img $R
for p in vendor system_ext product; do [ -f $I/$p.img ] && mnt $I/$p.img $R/$p; done
# Writable scratch where Android's init would put tmpfs.
for d in apex linkerconfig dev/socket mnt tmp; do :; done
mountpoint -q $R/apex || mount -t tmpfs tmpfs $R/apex
mountpoint -q $R/linkerconfig || mount -t tmpfs tmpfs $R/linkerconfig
mountpoint -q $R/data || { mkdir -p /var/lib/android-data; mount --bind /var/lib/android-data $R/data; }
# binderfs on the host first, so the /dev bind below already contains it.
mkdir -p /dev/binderfs; mountpoint -q /dev/binderfs || mount -t binder binder /dev/binderfs
for b in binder hwbinder vndbinder; do [ -e /dev/$b ] || ln -sf /dev/binderfs/$b /dev/$b; done
# 0666 like Android, so the GPU desktop (libhybris in the user session) can reach the allocator HAL.
chmod 666 /dev/binderfs/binder /dev/binderfs/hwbinder /dev/binderfs/vndbinder
for d in dev proc sys; do mountpoint -q $R/$d || mount --rbind /$d $R/$d; done
# APEXes: unpack each payload once to $I/apex, then mount it at /apex/<name> (and the short name).
mkdir -p $I/apex
for a in $R/system/apex/*.apex $R/system/apex/*.capex $R/vendor/apex/*.apex; do
  [ -f "$a" ] || continue
  n=$(basename "$a"); n=${n%.apex}; n=${n%.capex}
  if [ ! -s $I/apex/$n.img ]; then
    unzip -p "$a" apex_payload.img > $I/apex/$n.img 2>/dev/null
    # Compressed APEXes (*_compressed / .capex) wrap the real APEX as original_apex.
    if [ ! -s $I/apex/$n.img ] && unzip -l "$a" original_apex >/dev/null 2>&1; then
      unzip -p "$a" original_apex > $I/apex/$n.inner.apex && unzip -p $I/apex/$n.inner.apex apex_payload.img > $I/apex/$n.img
      rm -f $I/apex/$n.inner.apex
    fi
  fi
  [ -s $I/apex/$n.img ] || { rm -f $I/apex/$n.img; continue; }
  short=${n%%@*}; short=${short%.mediatek}; short=${short%_compressed}
  mkdir -p $R/apex/$n; mnt $I/apex/$n.img $R/apex/$n
  [ -e $R/apex/$short ] || ln -s $n $R/apex/$short
done
echo "apexes mounted: $(ls $R/apex | wc -l)"
ls -la $R/apex/com.android.runtime/bin/linker64 2>&1 | cut -c1-110
ls -la /dev/binder /dev/hwbinder /dev/vndbinder 2>&1 | cut -c1-80
du -sh $I 2>/dev/null
