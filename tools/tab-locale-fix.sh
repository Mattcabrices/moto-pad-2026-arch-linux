# Runs as root on the tablet: generate en_US.UTF-8 and make it the system locale (apps were running in "C",
# so UTF-8 text such as box-drawing characters rendered as junk in Claude Code / terminals).
echo "locale.conf: [$(cat /etc/locale.conf 2>/dev/null)]"; echo "generated: [$(locale -a 2>/dev/null | tr '\n' ' ')]"
grep -v '^#' /etc/locale.gen | grep . 
grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen 2>&1 | tail -2
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "now: [$(cat /etc/locale.conf)] generated: [$(locale -a | tr '\n' ' ')]"
