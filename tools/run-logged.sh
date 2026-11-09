#!/bin/bash
# Runs a build script with its log at LOG and appends rc=<exit code>. Usage: run-logged.sh LOG script [env assignments via env]
L=$1; shift
"$@" > "$L" 2>&1; echo "rc=$?" >> "$L"
