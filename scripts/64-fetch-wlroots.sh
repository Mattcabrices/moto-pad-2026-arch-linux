#!/bin/bash
# Fetches wlroots (same version as Arch's wlroots0.20, which labwc links) into /build/src. GPU port.
set -euo pipefail
V=0.20.2
cd /build/src
[ -s wlroots-$V.tar.gz ] || curl -sfL -o wlroots-$V.tar.gz https://gitlab.freedesktop.org/wlroots/wlroots/-/releases/$V/downloads/wlroots-$V.tar.gz \
  || curl -sfL -o wlroots-$V.tar.gz https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/$V/wlroots-$V.tar.gz
[ -d wlroots-$V ] || tar xzf wlroots-$V.tar.gz
ls -la wlroots-$V.tar.gz; du -sh wlroots-$V; ls wlroots-$V
