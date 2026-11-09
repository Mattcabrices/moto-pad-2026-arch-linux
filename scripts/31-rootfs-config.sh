#!/bin/bash
# Configures the Arch rootfs for the Moto Pad: stock modules and firmware, XFCE autologin,
# Xorg, and a USB debug network with SSH. Safe to re-run.
set -euo pipefail
R=/build/rootfs/root
S=/build/stock
O=/build/out
KREL=$(cat /build/kernel/out/include/config/kernel.release)
USERNAME=matt
mkdir -p "$O"

# --- Kernel modules: stock binaries, loaded in Android's order by pad-modules.service.
# No depmod and no modules.alias, so udev cannot autoload anything unexpected.
M="$R/usr/lib/modules/$KREL/archpad"
# Both images ship some modules under the same name, so each set keeps its own folder.
rm -rf "$R/usr/lib/modules"; mkdir -p "$M/first-stage" "$M/second-stage"
cp "$S"/vr/lib/modules/*.ko "$M/first-stage/"
cp "$S"/vendor_dlkm.d/lib/modules/*.ko "$M/second-stage/"
cp "$S"/vr/lib/modules/modules.{dep,softdep} "$M/first-stage/"
cp "$S"/vendor_dlkm.d/lib/modules/modules.{dep,softdep} "$M/second-stage/"
sed 's|.*/||' "$S/vr/lib/modules/modules.load" > "$M/first-stage.list"
# v1 leaves out the modem (needs Android RIL) and the camera stack (needs Android HALs).
sed 's|.*/||' "$S/vendor_dlkm.d/lib/modules/modules.load" \
  | grep -vE '^(ccci_|ccmni|c2k_|mddp|md_cooling|mtk_md_power|camera_|imgsensor|cam_qos|main[0-9]?af|sub[0-9]?af|flashlight)' \
  > "$M/second-stage.list"
echo "modules: $(ls "$M"/*/*.ko | wc -l) files, second stage loads $(wc -l < "$M/second-stage.list")"

# --- Firmware from stock vendor. The MTK drivers look in /vendor/firmware or the default path.
rm -rf "$R/usr/lib/firmware"; mkdir -p "$R/usr/lib/firmware" "$R/vendor"
cp -a "$S"/vendor.d/firmware/. "$R/usr/lib/firmware/"
ln -sfn /usr/lib/firmware "$R/vendor/firmware"

install -Dm755 /dev/stdin "$R/usr/local/sbin/pad-load-modules" <<'EOF'
#!/bin/sh
# Loads stock vendor modules in Android's order, dependencies and pre-softdeps first.
d=/usr/lib/modules/$(uname -r)/archpad
SEEN=" "
modname() { n=${1##*/}; n=${n%.ko}; echo "$n" | tr - _; }
find_ko() { for s in second-stage first-stage; do [ -f "$d/$s/$1" ] && { echo "$d/$s/$1"; return; }; done; }
load() {
  local m=$1 x p f
  case "$SEEN" in *" $m "*) return 0 ;; esac
  SEEN="$SEEN$m "
  grep -q "^$(modname "$m") " /proc/modules && return 0
  for p in $(cat "$d"/*/modules.softdep 2>/dev/null | grep "^softdep $(modname "$m") pre:" | sed 's/.*pre://'); do load "${p%.ko}.ko"; done
  for x in $(cat "$d"/*/modules.dep | grep -m1 "/$m:" | cut -d: -f2); do load "${x##*/}"; done
  f=$(find_ko "$m"); [ -n "$f" ] || { echo "missing: $m"; return 1; }
  insmod "$f" 2>/run/pad-insmod.err || { echo "failed: $m: $(cat /run/pad-insmod.err)"; return 1; }
}
for stage in first-stage second-stage; do
  while read -r m; do [ -n "$m" ] && load "${m##*/}"; done < "$d/$stage.list"
done
echo "pad-load-modules: $(grep -c '' /proc/modules) modules loaded"
EOF

install -Dm755 /dev/stdin "$R/usr/local/sbin/pad-usb-gadget" <<'EOF'
#!/bin/sh
# USB network to the PC: the tablet is 10.55.0.1 and hands the PC an address by DHCP.
g=/sys/kernel/config/usb_gadget/g1
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
if [ ! -d "$g" ]; then
  mkdir -p "$g/strings/0x409" "$g/configs/c.1" "$g/functions/ncm.usb0"
  echo 0x18d1 > "$g/idVendor"; echo 0x4e23 > "$g/idProduct"
  echo archpad > "$g/strings/0x409/serialnumber"
  echo "Arch Moto Pad" > "$g/strings/0x409/product"
  ln -s "$g/functions/ncm.usb0" "$g/configs/c.1/"
fi
n=0; while [ -z "$(ls /sys/class/udc 2>/dev/null)" ] && [ $n -lt 30 ]; do sleep 1; n=$((n + 1)); done
[ -n "$(cat "$g/UDC" 2>/dev/null)" ] || ls /sys/class/udc > "$g/UDC"
EOF

install -Dm755 /dev/stdin "$R/usr/local/sbin/pad-growfs" <<'EOF'
#!/bin/sh
# Grows the root filesystem to fill userdata once, on first boot.
resize2fs "$(findmnt -no SOURCE /)" && touch /var/lib/pad-growfs.done
EOF

install -Dm644 /dev/stdin "$R/etc/systemd/system/pad-modules.service" <<'EOF'
[Unit]
Description=Load stock Moto Pad kernel modules
DefaultDependencies=no
After=systemd-udevd.service
Before=sysinit.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/pad-load-modules
[Install]
WantedBy=sysinit.target
EOF

install -Dm644 /dev/stdin "$R/etc/systemd/system/pad-usb-gadget.service" <<'EOF'
[Unit]
Description=USB debug network to the PC
After=pad-modules.service
Before=systemd-networkd.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/pad-usb-gadget
[Install]
WantedBy=multi-user.target
EOF

install -Dm644 /dev/stdin "$R/etc/systemd/system/pad-growfs.service" <<'EOF'
[Unit]
Description=Grow root filesystem to fill userdata
ConditionPathExists=!/var/lib/pad-growfs.done
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pad-growfs
[Install]
WantedBy=multi-user.target
EOF

# Clears archinit's boot-loop marker once Arch has stayed up for two minutes.
install -Dm644 /dev/stdin "$R/etc/systemd/system/pad-boot-ok.service" <<'EOF'
[Unit]
Description=Mark this Arch boot as good (clears archinit's boot-loop marker)
After=multi-user.target
[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 120
ExecStart=/usr/bin/rm -f /var/lib/archpad/boot-pending
[Install]
WantedBy=multi-user.target
EOF

install -Dm644 /dev/stdin "$R/etc/systemd/network/50-usb0.network" <<'EOF'
[Match]
Name=usb0
[Network]
Address=10.55.0.1/24
DHCPServer=yes
[DHCPServer]
PoolOffset=10
PoolSize=5
EmitDNS=no
EmitRouter=no
EOF

install -Dm644 /dev/stdin "$R/etc/NetworkManager/conf.d/10-usb0-unmanaged.conf" <<'EOF'
[keyfile]
unmanaged-devices=interface-name:usb0
EOF

# --- Display: Xorg modesetting on the stock MediaTek DRM driver, software rendering.
install -Dm644 /dev/stdin "$R/etc/X11/xorg.conf.d/10-pad.conf" <<'EOF'
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection
Section "Device"
    Identifier "pad"
    Driver "modesetting"
    Option "kmsdev" "/dev/dri/card0"
    Option "AccelMethod" "none"
    Option "ShadowFB" "true"
    # The legacy hardware cursor oopses mediatek-drm; noplanes.so no-ops it and X draws its own.
    Option "SWcursor" "true"
    # Nothing is attached to the USB-C DisplayPort output, but it reports "connected" and
    # driving its CRTC oopses mediatek-drm. Ignore it.
    Option "Monitor-DP-1" "dp-ignored"
    Option "Monitor-DSI-1" "dsi-landscape"
EndSection
Section "Monitor"
    Identifier "dp-ignored"
    Option "Ignore" "true"
EndSection
EOF

# mediatek-drm workaround shim (tools/src/noplanes.c, built by scripts/55-build-tablet-tools.sh)
# and the X server wrapper that loads it. startx's default Xorg.wrap is setuid and drops LD_PRELOAD.
[ -f /build/out/tools/noplanes.so ] || { echo "ABORT: run scripts/55-build-tablet-tools.sh first"; exit 2; }
install -Dm755 /build/out/tools/noplanes.so "$R/usr/local/lib/noplanes.so"
install -Dm755 /build/out/tools/kmstest "$R/usr/local/bin/kmstest"
install -Dm755 /dev/stdin "$R/usr/local/bin/Xpad" <<'EOF'
#!/bin/sh
# X server for the Moto Pad: the real Xorg binary with the mediatek-drm workaround shim.
exec env LD_PRELOAD=/usr/local/lib/noplanes.so /usr/lib/Xorg "$@"
EOF

# XFCE scaled 2x for a high-density touch screen, with compositing off to save CPU.
install -Dm644 /dev/stdin "$R/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Gdk" type="empty">
    <property name="WindowScalingFactor" type="int" value="2"/>
  </property>
</channel>
EOF
install -Dm644 /dev/stdin "$R/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="theme" type="string" value="Default-xhdpi"/>
  </property>
</channel>
EOF

# Landscape from X server start (rotating after XFCE starts leaves it sized wrong); touch follows.
install -Dm644 /dev/stdin "$R/etc/X11/xorg.conf.d/20-pad-landscape.conf" <<'EOF'
Section "Monitor"
    Identifier "dsi-landscape"
    Option "Rotate" "right"
EndSection
Section "InputClass"
    Identifier "himax touch follows rotation"
    MatchProduct "himax-touchscreen"
    MatchIsTouchscreen "on"
    Option "TransformationMatrix" "0 1 0 -1 0 1 0 0 1"
EndSection
EOF

# Assistive technologies on, so Onboard can auto-show on text fields.
install -Dm644 /dev/stdin "$R/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="StartAssistiveTechnologies" type="bool" value="true"/>
  </property>
</channel>
EOF

# Autologin on tty1, then XFCE.
install -Dm644 /dev/stdin "$R/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF

# --- Wi-Fi: Android helpers in /opt/android (scripts/56-android-runtime.sh, 57-build-propshim.sh),
# started at boot by pad-wifi.service. fake-logd.py stands in for Android's logd.
T=/mnt/c/mpad26/MotoPadArch/tools
if [ -x /build/out/android-rt/system/bin/linker64 ] && [ -f /build/out/android-rt/system/lib64/libpropshim.so ]; then
  rm -rf "$R/opt/android"; mkdir -p "$R/opt/android"; cp -a /build/out/android-rt/. "$R/opt/android/"
  install -Dm755 $T/pad-wifi-start "$R/usr/local/sbin/pad-wifi-start"
  install -Dm755 $T/fake-logd.py "$R/usr/local/bin/fake-logd.py"
  install -Dm644 /dev/stdin "$R/etc/systemd/system/pad-wifi.service" <<'EOF'
[Unit]
Description=Bring up MediaTek Wi-Fi (Android helpers in /opt/android)
After=pad-modules.service
Before=NetworkManager.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/pad-wifi-start
TimeoutStartSec=120
[Install]
WantedBy=multi-user.target
EOF
  WIFI_UNIT=pad-wifi.service
else
  echo "WARNING: Android runtime not built; image will have no Wi-Fi (run scripts 56 and 57)"
  WIFI_UNIT=
fi

# --- Bluetooth: MediaTek /dev/stpbt bridged to hci_vhci (tools/pad-bt-bridge.py), after Wi-Fi.
BT_UNIT=
if [ -f /build/out/tools/hci_vhci.ko ] && [ -n "$WIFI_UNIT" ]; then
  install -Dm644 /build/out/tools/hci_vhci.ko "$M/extra/hci_vhci.ko"
  install -Dm755 $T/pad-bt-bridge.py "$R/usr/local/bin/pad-bt-bridge.py"
  install -Dm755 /dev/stdin "$R/usr/local/sbin/pad-bt-start" <<'EOF'
#!/bin/sh
eval "$(sed -n '/^d=/,/^}$/p' /usr/local/sbin/pad-load-modules)"
load bt_drv_connac1x.ko
grep -q '^hci_vhci ' /proc/modules || insmod /usr/lib/modules/$(uname -r)/archpad/extra/hci_vhci.ko
exec python3 /usr/local/bin/pad-bt-bridge.py
EOF
  install -Dm644 /dev/stdin "$R/etc/systemd/system/pad-bt.service" <<'EOF'
[Unit]
Description=Bluetooth bridge for MediaTek stpbt (hci0 via hci_vhci)
After=pad-wifi.service
Requires=pad-wifi.service
Before=bluetooth.service
[Service]
ExecStart=/usr/local/sbin/pad-bt-start
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
  BT_UNIT="pad-bt.service bluetooth.service"
fi

# --- Audio: speaker routing at boot (tools/pad-audio-speaker, from stock audio_device.xml).
install -Dm755 /mnt/c/mpad26/MotoPadArch/tools/pad-audio-speaker "$R/usr/local/sbin/pad-audio-speaker"
install -Dm755 /mnt/c/mpad26/MotoPadArch/tools/pad-audio-mic "$R/usr/local/sbin/pad-audio-mic"
install -Dm644 /mnt/c/mpad26/MotoPadArch/tools/90-pad-mic.conf "$R/etc/pipewire/pipewire.conf.d/90-pad-mic.conf"
install -Dm644 /dev/stdin "$R/etc/systemd/system/pad-audio.service" <<'EOF'
[Unit]
Description=Route audio to the Moto Pad speakers (codec line out + aw87xxx amps)
After=pad-modules.service sound.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sh -c 'for i in $(seq 30); do [ -e /dev/snd/controlC0 ] && exit 0; sleep 1; done'
ExecStart=/usr/local/sbin/pad-audio-speaker
[Install]
WantedBy=multi-user.target
EOF

# Onboard as a docked, auto-showing tablet keyboard (system-wide GSettings defaults).
install -Dm644 /dev/stdin "$R/usr/share/glib-2.0/schemas/90_archpad-onboard.gschema.override" <<'EOF'
[org.onboard]
layout='/usr/share/onboard/layouts/Phone.onboard'
theme='/usr/share/onboard/themes/Droid.theme'
show-status-icon=true
start-minimized=true
[org.onboard.window]
docking-enabled=true
docking-edge='bottom'
force-to-top=true
[org.onboard.window.landscape]
dock-expand=true
dock-height=260
[org.onboard.window.portrait]
dock-expand=true
dock-height=360
[org.onboard.auto-show]
enabled=true
[org.onboard.keyboard]
touch-input='multi'

[org.gnome.desktop.interface]
toolkit-accessibility=true
[org.gnome.desktop.a11y.applications]
screen-keyboard-enabled=true
EOF

# --- SSH key for USB debugging, generated on this PC and kept out of the image.
[ -f "$O/archpad_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C archpad-debug -f "$O/archpad_ed25519"

echo "archpad 1 kernel $KREL built $(date -u +%F)" > "$R/etc/archpad-release"
echo archpad > "$R/etc/hostname"
printf 'en_US.UTF-8 UTF-8\n' > "$R/etc/locale.gen"
echo 'LANG=en_US.UTF-8' > "$R/etc/locale.conf"
ln -sfn /usr/share/zoneinfo/America/New_York "$R/etc/localtime"
: > "$R/etc/fstab"

PUB=$(cat "$O/archpad_ed25519.pub")
arch-chroot "$R" /bin/bash -euo pipefail <<EOF
locale-gen >/dev/null
glib-compile-schemas /usr/share/glib-2.0/schemas
# The Arch Linux ARM default 'alarm' user is replaced by $USERNAME.
id alarm >/dev/null 2>&1 && userdel -r alarm 2>/dev/null || true
id $USERNAME >/dev/null 2>&1 || useradd -m -G wheel,video,input,audio -s /bin/bash $USERNAME
echo "$USERNAME:archpad" | chpasswd
echo "root:archpad" | chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel; chmod 440 /etc/sudoers.d/10-wheel
install -d -m700 -o $USERNAME -g $USERNAME /home/$USERNAME/.ssh
echo "$PUB" > /home/$USERNAME/.ssh/authorized_keys
chown $USERNAME:$USERNAME /home/$USERNAME/.ssh/authorized_keys; chmod 600 /home/$USERNAME/.ssh/authorized_keys
cat > /home/$USERNAME/.bash_profile <<'P'
[ -f ~/.bashrc ] && . ~/.bashrc
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = /dev/tty1 ] && [ ! -e ~/.no-x ]; then
  exec startx /usr/bin/startxfce4 -- /usr/local/bin/Xpad vt1 -keeptty > ~/.xorg-session.log 2>&1
fi
P
chown $USERNAME:$USERNAME /home/$USERNAME/.bash_profile
mkdir -p /home/$USERNAME/.config; echo "--force-renderer-accessibility" > /home/$USERNAME/.config/chromium-flags.conf
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config
# Onboard on-screen keyboard starts with the desktop.
install -d -o $USERNAME -g $USERNAME /home/$USERNAME/.config/autostart
[ -f /etc/xdg/autostart/onboard-autostart.desktop ] && cp /etc/xdg/autostart/onboard-autostart.desktop /home/$USERNAME/.config/autostart/ && chown $USERNAME:$USERNAME /home/$USERNAME/.config/autostart/onboard-autostart.desktop
systemctl enable pad-modules.service pad-usb-gadget.service pad-growfs.service pad-boot-ok.service \
  systemd-networkd.service NetworkManager.service sshd.service >/dev/null 2>&1
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 || true
systemctl disable systemd-networkd-wait-online.service NetworkManager-wait-online.service >/dev/null 2>&1 || true
EOF

du -sh "$R"
echo CONFIG_DONE
