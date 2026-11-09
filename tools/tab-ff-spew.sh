# Runs on the tablet: GL spew lines around context creation failures from /tmp/ff-spew.log.
wc -l < /tmp/ff-spew.log
grep -n -i -E 'fail|error|GLES|version|es2|es3|robust|context|0x30' /tmp/ff-spew.log | grep -v -E 'channel error|^\s*$' | cut -c1-180 | head -60
