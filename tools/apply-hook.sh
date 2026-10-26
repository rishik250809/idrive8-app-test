#!/bin/sh

set -eu
MAIN=/usr/lib/oap-mainapp21/src/main.js
PLATFORM=/var/opt/public/oap/_id8_bench_demo
[ -f "$PLATFORM/enabled" ] && [ -f "$PLATFORM/main.js" ] || exit 0
grep -q " $MAIN " /proc/mounts && exit 0
if [ "$(sha256sum "$MAIN" | cut -d ' ' -f1)" != c96c81653952fd9b24e2718cead75b18c1a1d5be7b336f6f7053ce3c23490b33 ]; then
    echo 'ID8 Bench Test: firmware changed; provisioning hook not applied' >&2
    exit 0
fi
mount --bind "$PLATFORM/main.js" "$MAIN"
