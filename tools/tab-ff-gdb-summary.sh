grep -E "^CREATE|^MAKECURRENT|Value returned|Run till exit" /tmp/ff-gdb.log | grep -v "Run till" | head -40
