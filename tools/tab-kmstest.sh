chmod +x /tmp/kmstest
timeout 20 /tmp/kmstest 10 2>&1
echo "kmstest exit: $?"
