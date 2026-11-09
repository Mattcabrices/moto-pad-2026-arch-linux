#!/bin/bash
# Runs in WSL: executes a local script as root on the tablet over SSH.
# Usage: pad-sudo.sh /path/to/script.sh
# The first line sent is matt's sudo password. It is read from tools/.pad-password (git-ignored; one line);
# without that file the fresh-image default "archpad" is used. Change the tablet's password and put it there.
P=/mnt/c/mpad26/MotoPadArch/tools/.pad-password
PW=archpad; [ -s "$P" ] && PW=$(head -1 "$P")
{ echo "$PW"; cat "$1"; } | bash /mnt/c/mpad26/MotoPadArch/tools/pad-ssh.sh "sudo -S -p '' bash -s"
