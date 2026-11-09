# Runs as root on the tablet: install BlueZ/Blueman, the BT bridge, and try bringing up hci0.
eval "$(sed -n '/^d=/,/^}$/p' /usr/local/sbin/pad-load-modules)"
pacman -S --noconfirm --needed bluez bluez-utils blueman 2>&1 | tail -2
install -Dm644 /tmp/hci_vhci.ko /usr/lib/modules/$(uname -r)/archpad/extra/hci_vhci.ko
install -Dm755 /tmp/pad-bt-bridge.py /usr/local/bin/pad-bt-bridge.py
load bt_drv_connac1x.ko; insmod /usr/lib/modules/$(uname -r)/archpad/extra/hci_vhci.ko 2>&1
ls -la /dev/stpbt /dev/vhci 2>&1
pkill -f pad-bt-bridge.py; (nohup python3 /usr/local/bin/pad-bt-bridge.py > /tmp/bt-bridge.log 2>&1 &)
sleep 3; systemctl start bluetooth; sleep 6
cat /tmp/bt-bridge.log
btmgmt info 2>&1 | head -8
