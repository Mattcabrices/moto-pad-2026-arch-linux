grep -c gles2_cmd_decoder_passthrough /tmp/chr.log
grep gles2_cmd_decoder_passthrough /tmp/chr.log | sed 's/.*cmd: //' | sort | uniq -c | sort -rn | head -30
echo ---; grep -n gles2_cmd_decoder_passthrough /tmp/chr.log | tail -12 | cut -c1-200
grep -n CONTEXT_LOST /tmp/chr.log | cut -c1-120
