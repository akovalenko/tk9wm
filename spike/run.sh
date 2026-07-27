#!/bin/sh
# tk9wm spike driver — everything in ONE sandbox Bash call (namespaces are
# per-call, so Xvfb must live and die inside this script).
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../../whalebuild/work/linux}"
export DISPLAY=:77
Xvfb :77 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

echo "=== A: Tk-level bind <MapRequest> on a widget ==="
"$LINUX/whale" "$HERE/test-a.tcl"
echo
echo "=== C: cffi redirect on root + real client ==="
"$LINUX/whale-cli" "$HERE/test-c-wm.tcl" &
WM=$!
sleep 1
"$LINUX/whale" "$HERE/client.tcl"
wait $WM
