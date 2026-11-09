#!/bin/bash
# Waits (up to ~9 min) for a background build log to end with rc=, then prints its tail. Usage: wait-log.sh LOG
for i in $(seq 105); do grep -q "^rc=" "$1" 2>/dev/null && break; sleep 5; done
tail -25 "$1"
