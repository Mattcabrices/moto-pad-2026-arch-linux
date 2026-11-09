#!/bin/bash
# Builds the minimal XFCE Arch Linux ARM root filesystem in /build/rootfs/root.
set -euo pipefail
R=/build/rootfs/root
T=/build/rootfs/ArchLinuxARM-aarch64-latest.tar.gz
# The HTTPS certificate on this host did not match its name on 2026-11-06. The project's
# official downloads use HTTP; integrity comes from the pinned-key signature check below.
URL=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
ALARM_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6

PKGS=(
  xorg-server xf86-input-libinput xorg-xinit xorg-xrandr xorg-xinput
  xfce4-session xfwm4 xfce4-panel xfdesktop xfce4-settings xfconf
  thunar xfce4-terminal
  ttf-dejavu adwaita-icon-theme
  networkmanager network-manager-applet polkit
  openssh sudo e2fsprogs
  chromium onboard
  bluez bluez-utils blueman
  alsa-utils pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol xfce4-pulseaudio-plugin
)

mkdir -p /build/rootfs
if [ ! -f "$T" ]; then
  curl -fsSL -m 1800 -o "$T" "$URL"
  curl -fsSL -m 60 -o "$T.sig" "$URL.sig"
fi
gpg --list-keys "$ALARM_KEY" >/dev/null 2>&1 \
  || gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$ALARM_KEY" \
  || gpg --keyserver hkps://keys.openpgp.org --recv-keys "$ALARM_KEY"
if ! gpg --status-fd 1 --verify "$T.sig" "$T" 2>/dev/null | grep -q "VALIDSIG .*$ALARM_KEY"; then
  echo "ABORT: tarball signature is not valid for $ALARM_KEY"
  rm -f "$T" "$T.sig"
  exit 3
fi
echo "signature OK: $ALARM_KEY"

if [ ! -f "$R/etc/arch-release" ]; then
  rm -rf "$R"; mkdir -p "$R"
  bsdtar -xpf "$T" -C "$R"
fi

# Skip docs and foreign locales to keep the image small.
grep -q '^NoExtract = usr/share/doc' "$R/etc/pacman.conf" || sed -i '/^\[options\]/a NoExtract = usr/share/doc/* usr/share/man/* usr/share/info/* usr/share/gtk-doc/* usr/share/help/*\nNoExtract = usr/share/locale/* !usr/share/locale/en* !usr/share/locale/locale.alias' "$R/etc/pacman.conf"

# pacman's download sandbox fails under qemu-user during this build. Package signatures
# are still checked. Kept in the final image only if the tablet kernel lacks Landlock.
grep -q '^DisableSandbox' "$R/etc/pacman.conf" || sed -i '/^\[options\]/a DisableSandbox' "$R/etc/pacman.conf"

cp -L /etc/resolv.conf "$R/etc/resolv.conf" 2>/dev/null || true
# pacman's free-space check needs the root to be a mount point.
mountpoint -q "$R" || mount --bind "$R" "$R"
arch-chroot "$R" /bin/bash -euxo pipefail <<EOF
pacman-key --init
pacman-key --populate archlinuxarm
# The tablet boots its own kernel, so drop these before upgrading to avoid downloading them.
for p in linux-aarch64 \$(pacman -Qq | grep '^linux-firmware' || true); do
  pacman -Rdd --noconfirm "\$p" || true
done
pacman -Syu --noconfirm --needed busybox ${PKGS[*]}
orphans=\$(pacman -Qdtq || true)
[ -z "\$orphans" ] || pacman -Rns --noconfirm \$orphans || true
rm -rf /var/cache/pacman/pkg/* /usr/share/doc/* /usr/share/man/*
EOF

du -sh "$R"
du -sh "$R/usr/lib" "$R/usr/share"
echo "busybox: $(file -b "$R/usr/bin/busybox" | cut -c1-70)"
echo ROOTFS_DONE
