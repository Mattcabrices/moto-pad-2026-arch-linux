#!/bin/bash
# Shallow-fetches the exact stock GKI kernel source. Source only; nothing is executed.
set -uo pipefail
SHA=051a97cf151a
K=/build/kernel/src
GITILES=https://android.googlesource.com

if [ ! -f "$K/Makefile" ]; then
  mkdir -p "$K"; cd "$K"; git init -q . 2>/dev/null
  git remote add origin "$GITILES/kernel/common" 2>/dev/null
  # Git needs the full hash for a shallow fetch, so resolve it through gitiles.
  FULL=$(curl -sS -m 60 "$GITILES/kernel/common/+/$SHA?format=JSON" | sed 1d | python3 -c 'import json,sys;print(json.load(sys.stdin)["commit"])')
  echo "full sha: ${FULL:-unresolved}"
  [ -n "$FULL" ] || exit 2
  git fetch --depth 1 --no-tags origin "$FULL" || exit 3
  git checkout -q FETCH_HEAD || exit 4
fi
git -C "$K" log -1 --format='%h %ad %s' --date=short
du -sh "$K"
echo FETCH_DONE
