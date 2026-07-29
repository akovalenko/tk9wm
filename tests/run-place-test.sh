#!/bin/sh
# Regression for client positioning (USPosition/PPosition): a client
# that CLAIMS its position gets it, everyone else keeps the cascade.
# Actors, in manage order:
#   P (старожил)       maps at +430+300 BEFORE the WM — adoption must
#                      keep the claimed spot
#   A (верхний-правый) -geometry style +500+50 — placed verbatim
#   B (кочевник)       no position — cascades; later asks to move to
#                      +120+200 (wm geometry with USPosition) and the
#                      move is honored
#   M (главное)        dialog leader, no position — cascades
#   D (диалог)         transient with its OWN +150+90 — the claim
#                      beats the centering
. "$(dirname "$0")/common.sh"
export DISPLAY=:97
rm -f /tmp/.X97-lock /tmp/.X11-unix/X97
Xvfb :97 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/client.tcl" "старожил" 200x100+430+300 "#ad7fa8" "" "" 20 &
CP=$!
sleep 1                                   # maps wild, no WM yet

"$LINUX/whale" "$WMTCL" > "$HERE/wm-place.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "верхний-правый" 240x120+500+50 "#8ae234" "" "" 20 &
CA=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "кочевник" 240x120 "#fce94f" 260x140+120+200 "" 20 &
CB=$!
sleep 0.5
"$LINUX/whale" "$HERE/client-dlg.tcl" 300x200 260x180+150+90 &
CD=$!
sleep 6      # B's move request fires at its own t+4s; the dialog at t+2s

import -display :97 -window root "$HERE/place-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/place-test.png"

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-place.log")
PID=$1; AID=$2; BID=$3; MID=$4; DID=$5
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-place.log" | head -1)
BX=$(xwininfo -id "$BID" | awk '/Absolute upper-left X/ {print $NF}')
BY=$(xwininfo -id "$BID" | awk '/Absolute upper-left Y/ {print $NF}')

kill $WM $CP $CA $CB $CD 2>/dev/null

echo "--- actors: P=$PID A=$AID B=$BID M=$MID D=$DID (deco top=$TOP)"
echo "--- placement lines:"
grep -E 'frame \.f[0-9]+ for|move 0x' "$HERE/wm-place.log"

frame_at() { grep -q "for $1 at +$2$" "$HERE/wm-place.log"; }

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-place.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$DID" ]; then
    echo "FAIL: missing actor ids (P=$PID A=$AID B=$BID M=$MID D=$DID)"
fi
if frame_at "$PID" "430+300"; then
    echo "OK: the adopted claimant kept its +430+300"
else
    echo "FAIL: adopted claimant not at +430+300"
fi
if frame_at "$AID" "500+50"; then
    echo "OK: the -geometry claimant landed verbatim at +500+50"
else
    echo "FAIL: claimant not at +500+50"
fi
if frame_at "$BID" "120+200"; then
    echo "FAIL: the no-position client was NOT cascaded (born at +120+200)"
else
    echo "OK: the no-position client cascaded first"
fi
if grep -q "move $BID -> +120+200 (client request)" "$HERE/wm-place.log"; then
    echo "OK: the later wm-geometry move was honored"
else
    echo "FAIL: no honored move line for B"
fi
if [ "$BX" = 126 ] && [ "$BY" = "$((200 + TOP))" ]; then
    echo "OK: B's client area really sits at +126+$((200 + TOP))"
else
    echo "FAIL: B's client area at +$BX+$BY, want +126+$((200 + TOP))"
fi
if frame_at "$DID" "150+90"; then
    echo "OK: the dialog's own +150+90 beat the centering"
else
    echo "FAIL: dialog not at +150+90"
fi
if grep -q 'handler error' "$HERE/wm-place.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-place.log"
fi
