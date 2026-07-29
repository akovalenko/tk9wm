#!/bin/sh
# Regression for the close wink: a WM_DELETE_WINDOW that goes
# unanswered (the client is hung, or just refuses) must be made
# visible — the frame winks — while a client that closes in time
# must produce no wink at all. Actors, in manage order:
#   S (молчун)     ignores WM_DELETE_WINDOW (client-stubborn.tcl)
#   C (закрывашка) exits on it (client.tcl)
# Both are closed through the ops menu (Alt+Space, hotkey c): C first
# (it dies, focus falls back to S), then S (it stays, the wink fires).
. "$(dirname "$0")/common.sh"
export DISPLAY=:94
rm -f /tmp/.X94-lock /tmp/.X11-unix/X94
Xvfb :94 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-wink.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client-stubborn.tcl" &
CS=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "закрывашка" 240x120 "#8ae234" "" "" 30 &
CC=$!
sleep 1

key() { xdotool key "$@"; sleep 0.5; }

key alt+space   # winops on C (focused last)
key c           # close -> C exits, S regains the focus
sleep 2.5       # past the grace period: C must NOT produce a wink
key alt+space   # winops on S
key c           # close -> ignored
sleep 3         # the grace period passes, the wink fires

kill $WM $CS $CC 2>/dev/null

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-wink.log")
SID=$1; CID=$2
echo "--- actors: S=$SID C=$CID"
echo "--- close/wink lines:"
grep -E 'close |wink|unmanaged' "$HERE/wm-wink.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-wink.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$SID" ] || [ -z "$CID" ]; then
    echo "FAIL: missing actor ids (S=$SID C=$CID)"
fi
if grep -q "close $CID: sending WM_DELETE_WINDOW" "$HERE/wm-wink.log" \
        && grep -q "unmanaged $CID" "$HERE/wm-wink.log"; then
    echo "OK: the compliant client was asked politely and left"
else
    echo "FAIL: no polite close (or no exit) for the compliant client"
fi
if grep -q "close $CID: unanswered" "$HERE/wm-wink.log"; then
    echo "FAIL: the compliant client was declared silent"
else
    echo "OK: no wink for the client that closed in time"
fi
if grep -q "close $SID: unanswered after" "$HERE/wm-wink.log" \
        && grep -q "wink $SID" "$HERE/wm-wink.log"; then
    echo "OK: the stubborn client was declared silent and winked at"
else
    echo "FAIL: no unanswered/wink lines for the stubborn client"
fi
if grep -q 'handler error' "$HERE/wm-wink.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-wink.log"
fi
