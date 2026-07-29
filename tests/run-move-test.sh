#!/bin/sh
# ICCCM 4.1.5 regression: a ConfigureWindow request the WM does not grant
# must still be answered with a synthetic ConfigureNotify. A WM that stays
# silent leaves the client believing its move took effect — the root of
# the live "the app does not know where it is" report (menus, tooltips,
# combo dropdowns and clicks all offset, until the first drag).
. "$(dirname "$0")/common.sh"
export DISPLAY=:85
rm -f /tmp/.X85-lock /tmp/.X11-unix/X85
Xvfb :85 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-move.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale-cli" "$HERE/client-move.tcl" :85
kill $WM 2>/dev/null

echo "--- what the WM logged:"
grep -E 'managed 0x|ConfigureRequest|resize 0x' "$HERE/wm-move.log" | head -5
if grep -q 'BadAccess request=2' "$HERE/wm-move.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
