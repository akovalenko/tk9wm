#!/bin/sh
# Regression: wm withdraw + wm deiconify must not kill the client, and the
# deiconify must get re-managed into a fresh frame.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client-w.tcl"
kill $WM 2>/dev/null
