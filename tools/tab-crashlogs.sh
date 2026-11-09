cat /tmp/archinit.log;
echo ---pstore; ls -la /newroot/var/log/pstore/* 2>&1 | tail -8;
echo ---journal; ls /newroot/var/log/journal/*/ 2>&1 | tail -4
