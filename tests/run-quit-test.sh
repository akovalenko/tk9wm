#!/bin/sh
# Regression for Quit — the way out of the desk.
#
# The default chord must end the window manager, and it must end it the
# way a window manager should end: every client RELEASED and still
# alive on the root, at its own place, ready for whatever manages the
# screen next. A quit that took the clients with it would be worse than
# no quit at all, because the frames are ours and a client reparented
# into one goes down with it unless it is deliberately let go.
#
# Also checked: the process really exits (that is what ends the X
# session when .Xsession exec'd it), and it says so rather than dying
# quietly.
. "$(dirname "$0")/common.sh"
export DISPLAY=:96
rm -f /tmp/.X96-lock /tmp/.X11-unix/X96
Xvfb :96 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-quit.log" 2>&1 &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" "переживи выход" 260x160 "#729fcf" "" "" 40 \
    > "$HERE/quit-client.log" 2>&1 &
CL=$!
sleep 2
WID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-quit.log" | head -1)
FRAMED=$(xwininfo -id "$WID" -children 2>/dev/null \
    | sed -n 's/^  Parent window id: \(0x[0-9a-f]*\).*/\1/p')
ROOTID=$(xwininfo -root 2>/dev/null | sed -n 's/^xwininfo: Window id: \(0x[0-9a-f]*\).*/\1/p')
echo "--- client $WID, framed by $FRAMED (root is $ROOTID)"

# the default way out: Super+t q
xdotool key super+t; sleep 0.3; xdotool key q
sleep 2

ALIVE=1; kill -0 $WM 2>/dev/null || ALIVE=0
CLIENT_ALIVE=1; kill -0 $CL 2>/dev/null || CLIENT_ALIVE=0
STATE=$(xwininfo -id "$WID" 2>/dev/null | sed -n 's/.*Map State: //p')
PARENT=$(xwininfo -id "$WID" -children 2>/dev/null \
    | sed -n 's/^  Parent window id: \(0x[0-9a-f]*\).*/\1/p')
echo "--- after Super+t q: wm alive=$ALIVE client alive=$CLIENT_ALIVE state=$STATE parent=$PARENT"
kill $WM $CL 2>/dev/null

echo "--- WM saw:"
grep -E 'quit|bye|release|unmanaged' "$HERE/wm-quit.log" | tail -8

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$HERE/wm-quit.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
if [ "$FRAMED" != "$ROOTID" ] && [ -n "$FRAMED" ]; then
    echo "OK: the client really was framed before the quit ($FRAMED)"
else
    echo "FAIL: the client was never framed — the quit proves nothing"; BAD=1
fi
if [ "$ALIVE" = "0" ] && grep -q 'quit requested' "$HERE/wm-quit.log"; then
    echo "OK: Super+t q ended the window manager, and it said so"
else
    echo "FAIL: WM alive=$ALIVE, or no quit line in the log"; BAD=1
fi
if [ "$CLIENT_ALIVE" = "1" ] && [ "$STATE" = "IsViewable" ]; then
    echo "OK: the client outlived the window manager, still on screen"
else
    echo "FAIL: client alive=$CLIENT_ALIVE state=$STATE — the quit took it along"
    BAD=1
fi
if [ "$PARENT" = "$ROOTID" ]; then
    echo "OK: ...and was handed back to the root, ready for the next WM"
else
    echo "FAIL: the client's parent is $PARENT, want the root $ROOTID"; BAD=1
fi
if grep -q 'soft failure\|handler error' "$HERE/wm-quit.log"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$HERE/wm-quit.log"; BAD=1
fi

[ $BAD -eq 0 ] && echo "OK: the desk can be left from the inside, and leaves nothing broken"
exit $BAD
