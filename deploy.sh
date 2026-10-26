#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MGU_HOST=${MGU_HOST:-mgu}
REMOTE=/var/opt/id8-bench-demo-kit
cmd=${1:-check}; [ $# -eq 0 ] || shift
case "$cmd" in check|install|status|uninstall) ;; *) echo 'Usage: sh deploy.sh check|install|status|uninstall [--reuse-existing-hook] [--persist]' >&2; exit 2;; esac
for flag in "$@"; do
    case "$flag" in --reuse-existing-hook|--persist) ;; *) echo "Unknown option: $flag" >&2; exit 2;; esac
done
case "$MGU_HOST" in ''|*[!a-zA-Z0-9_.@:-]*) echo 'Invalid MGU_HOST' >&2; exit 2;; esac
if [ "$cmd" = check ] || [ "$cmd" = install ]; then
    [ -f "$ROOT/dist/id8-bench-test.tar.gz" ] || { echo 'Run python3 tools/build.py first' >&2; exit 1; }
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$MGU_HOST" "if [ -e $REMOTE ]; then test -f $REMOTE/.id8-bench-test-kit; else mkdir -m 700 $REMOTE && touch $REMOTE/.id8-bench-test-kit; fi"
    scp -o BatchMode=yes -o ConnectTimeout=10 "$ROOT/dist/id8-bench-test.tar.gz" "$MGU_HOST:$REMOTE/kit.tar.gz"
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$MGU_HOST" "cd $REMOTE && tar xzf kit.tar.gz && sh mgu.sh $cmd $*"
else
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$MGU_HOST" "test -f $REMOTE/.id8-bench-test-kit && cd $REMOTE && sh mgu.sh $cmd $*"
fi
