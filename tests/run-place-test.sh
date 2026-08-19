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
#
# ...and the PROGRAM's claim on its own, which is a different word from
# the user's and gets its own knob (`pposition`, see pposition-of):
#   S (сомнительный)   PPosition +0+0, default style — DOUBTED, because
#                      (0,0) is what an unfilled struct says, and the
#                      window cascades
#   H (честный)        the same +0+0 under `pposition honor` — believed,
#                      corner and all
#   I (слепой)         PPosition +400+300 under `pposition ignore` — not
#                      read at all: cascaded, and its later move request
#                      refused
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/place-config"; mkdir -p "$HERE/place-config"
cat > "$HERE/place-config/tk9wm.tcl" <<'EOF'
wm-style {filter -title честный} {pposition honor}
wm-style {filter -title слепой}  {pposition ignore}
EOF

"$LINUX/whale" "$HERE/client.tcl" "старожил" 200x100+430+300 "#ad7fa8" "" "" 20 &
CP=$!
sleep 1                                   # maps wild, no WM yet

XDG_CONFIG_HOME="$HERE/place-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-place.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-place.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "верхний-правый" 240x120+500+50 "#8ae234" "" "" 20 &
CA=$!
wait_client "$HERE/wm-place.log" 'верхний-правый'
"$LINUX/whale" "$HERE/client.tcl" "кочевник" 240x120 "#fce94f" 260x140+120+200 "" 20 &
CB=$!
wait_client "$HERE/wm-place.log" 'кочевник'
"$LINUX/whale" "$HERE/client-dlg.tcl" 300x200 260x180+150+90 &
CD=$!
sleep 6      # B's move request fires at its own t+4s; the dialog at t+2s

# --- the PROGRAM's claim, three readings of the same +0+0
"$LINUX/whale" "$HERE/client-pclaim.tcl" сомнительный 240x120+0+0 "#8ae234" 20 &
CS=$!
wait_client "$HERE/wm-place.log" 'сомнительный'
"$LINUX/whale" "$HERE/client-pclaim.tcl" честный 240x120+0+0 "#fce94f" 20 &
CH=$!
wait_client "$HERE/wm-place.log" 'честный'
"$LINUX/whale" "$HERE/client-pclaim.tcl" слепой 240x120+400+300 "#729fcf" 20 +200+150 &
CI=$!
wait_client "$HERE/wm-place.log" 'слепой'
sleep 6      # past the ignored client's own move request at t+4.4s

import -display "$DISPLAY" -window root "$HERE/place-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/place-test.png"

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-place.log")
PID=$1; AID=$2; BID=$3; MID=$4; DID=$5
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-place.log" | head -1)
BX=$(xwininfo -id "$BID" | awk '/Absolute upper-left X/ {print $NF}')
BY=$(xwininfo -id "$BID" | awk '/Absolute upper-left Y/ {print $NF}')

SID=$6; HID=$7; IID=$8

kill $WM $CP $CA $CB $CD $CS $CH $CI 2>/dev/null

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
if frame_at "$SID" "0+0"; then
    echo "FAIL: a program-said (0,0) was believed under the default — every\
 toolkit stamps that, and the corner would fill up"
else
    echo "OK: program-said (0,0) is doubted by default — the window cascaded"
fi
if frame_at "$HID" "0+0"; then
    echo "OK: ...and «pposition honor» takes the program at its word"
else
    echo "FAIL: under «pposition honor» the +0+0 claimant is not at +0+0"
fi
if frame_at "$IID" "400+300"; then
    echo "FAIL: «pposition ignore» still read the claim (born at +400+300)"
else
    echo "OK: «pposition ignore» never read the claim — the desk placed it"
fi
if grep -q "move request from $IID refused — pposition ignore" "$HERE/wm-place.log"; then
    echo "OK: ...and its later move request was refused for the same reason"
else
    echo "FAIL: the ignored client moved itself anyway — the knob holds only\
 until the client asks twice"
fi
if grep -q 'handler error' "$HERE/wm-place.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-place.log"
fi
