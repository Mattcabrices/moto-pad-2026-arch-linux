# Runs as root on the tablet: breaks the charger log feedback loop and caps the journal.
# Loop: journald enriches each kernel message with device info by reading the device's sysfs uevent; for the
# MediaTek/sc8960x chargers that read makes the driver printk 4 more lines, which journald reads again, forever
# (~100k lines/min, journald ~50% CPU). With ReadKMsg=no journald ignores /dev/kmsg; kernel logs stay in `dmesg`.
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/archpad.conf <<'EOF'
# Moto Pad (archpad): see tools/tab-journald-fix.sh in the project for why.
[Journal]
ReadKMsg=no
SystemMaxUse=200M
RuntimeMaxUse=50M
EOF
systemctl restart systemd-journald
sleep 5
journalctl --vacuum-size=200M 2>&1 | tail -1
journalctl --disk-usage
echo "lines in last 5 s: $(journalctl --since '-5s' --no-pager -o cat | wc -l)"
sleep 10
echo "journald CPU (10 s sample):"; top -b -n2 -d5 -p $(pgrep -x systemd-journal) | tail -2
uptime
echo "dmesg still works: $(dmesg | tail -1 | cut -c1-80)"
