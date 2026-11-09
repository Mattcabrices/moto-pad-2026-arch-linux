# Runs as root on the tablet: start the fake logd, restart wmt_launcher, and show what it logs.
install -Dm755 /tmp/fake-logd.py /usr/local/bin/fake-logd.py
pkill -f fake-logd.py; pkill -f wmt_launcher; sleep 1
(nohup python3 /usr/local/bin/fake-logd.py > /tmp/android-log.txt 2>&1 &)
sleep 2
(chroot /opt/android /vendor/bin/wmt_launcher -p /vendor/firmware/ -o 1 >/dev/null 2>&1 &)
sleep 10
echo "--- helper log"; tail -40 /tmp/android-log.txt
