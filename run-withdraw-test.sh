#!/bin/sh
# Regression: wm withdraw + wm deiconify must not kill the client, and the
# deiconify must get re-managed into a fresh frame.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:81
rm -f /tmp/.X81-lock /tmp/.X11-unix/X81
Xvfb :81 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client-w.tcl"
kill $WM 2>/dev/null
