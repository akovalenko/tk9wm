#!/bin/sh
# Regression for EWMH _NET_FRAME_EXTENTS: a client cannot measure its
# own decoration (its geometry is INSIDE the frame), and toolkits use
# the property to place what they position by the window rather than by
# the widget — menus anchored to a corner, "remember my position"
# arithmetic, input-method popups. Two paths: the property on a managed
# window, and the answer to a client that ASKS before its first map
# (_NET_REQUEST_FRAME_EXTENTS, sent to the root about a window that has
# no frame yet).
. "$(dirname "$0")/common.sh"
export DISPLAY=:95
rm -f /tmp/.X95-lock /tmp/.X11-unix/X95
Xvfb :95 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-extents.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "рамочный" 240x120 "#8ae234" "" "" 30 \
    > "$HERE/extents-framed.log" 2>&1 &
CA=$!
sleep 1.5
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-extents.log" | head -1)
FRAMED=$(xprop -id "$AID" _NET_FRAME_EXTENTS 2>/dev/null | sed 's/.*= //')

# ...and the ask-before-map path, in its own process
"$LINUX/whale" "$HERE/extents-client.tcl" > "$HERE/extents-ask.log" 2>&1
ASKED=$(sed -n 's/^EXTENTS-CLIENT: answer «\(.*\)»/\1/p' "$HERE/extents-ask.log")

kill $CA 2>/dev/null
sleep 0.5
kill $WM 2>/dev/null
sleep 0.5

# The decoration's own numbers, from the WM's own metric line
set -- $(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-extents.log" | head -1)
TOP=$1
B=6                       # the border, all four sides (policy.tcl)
WANT="$B, $B, $TOP, $B"
WANTL="$B $B $TOP $B"

echo "--- managed 0x… = «$FRAMED», asked-before-map = «$ASKED», want «$WANT»"
grep -E 'frame extents' "$HERE/wm-extents.log"

echo "--- verdict"
if [ "$FRAMED" = "$WANT" ]; then
    echo "OK: a managed window carries its frame extents"
else
    echo "FAIL: managed window says «$FRAMED», want «$WANT»"
fi
if grep -q 'frame extents requested' "$HERE/wm-extents.log"; then
    echo "OK: the request reached the WM"
else
    echo "FAIL: no _NET_REQUEST_FRAME_EXTENTS line in the log"
fi
if [ "$ASKED" = "$WANTL" ]; then
    echo "OK: a window with no frame yet got the same honest numbers"
else
    echo "FAIL: the asker got «$ASKED», want «$WANTL»"
fi
if grep -q 'handler error' "$HERE/wm-extents.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-extents.log"
fi
