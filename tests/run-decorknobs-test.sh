#!/bin/sh
# Regression for the decoration-number knobs. set-border N is the
# frame border on all four sides — the resize grip — and everything
# derived follows it: the client offset (decotop), the published
# extents, the titlebar button size. set-grips N is the corner arms'
# reach along the border, drawn (deco canvas) and hit-tested (rz-edge)
# from the same chrome verdict. Three paths: a config says the numbers
# at boot; the knobs move them LIVE (the wish settles on idle — a
# border change re-lays every frame and republishes extents, a grips
# change repaints and re-hit-tests with NO re-layout); an empty-config
# reload puts the stock numbers back.
. "$(dirname "$0")/common.sh"
start_xvfb

CONF="$HERE/decorknobs-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-border 10
set-grips 40
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-decorknobs.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-decorknobs.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "рамочный" 240x120 "#8ae234" "" "" 60 \
    > "$HERE/decorknobs-client.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-decorknobs.log" 'рамочный'
CID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-decorknobs.log" | head -1)

q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1; }
extents() { xprop -id "$CID" _NET_FRAME_EXTENTS 2>/dev/null | sed 's/.*= //'; }
extents_is() { [ "$(extents)" = "$1" ]; }
# the LAST metric line: the config's set-border already re-derived
# once by the time wait_wm answers, so the first line is the stock 6
metrics() { sed -n 's/^WM: titlebar h=\([0-9]*\) top=\([0-9]*\) btn=\([0-9]*\).*/\1 \2 \3/p' \
    "$HERE/wm-decorknobs.log" | tail -1; }
# the drawn grip arm: the first grip rectangle deco-draw puts down is
# {0 0 B CZ}, so its fourth coordinate IS the arm's reach
grip_len() { q 'set t $::frameof([lindex [array names ::frameof] 0])
lindex [$t.deco coords [lindex [$t.deco find withtag grip] 0]] 3'; }
grip_is() { [ "$(grip_len)" = "$1" ]; }

# --- the config path: both numbers spoken at boot
set -- $(metrics); H=$1; TOP=$2; BTN=$3
E0=$(extents)
G0=$(grip_len)
D0=$(q 'set t $::frameof([lindex [array names ::frameof] 0])
rz-edge $t 5 35')

# --- live grips: repaint and re-hit-test, no re-layout
q 'set-grips 12' >/dev/null
wait_for 10 grip_is 12.0
G1=$(grip_len)
D1=$(q 'set t $::frameof([lindex [array names ::frameof] 0])
rz-edge $t 5 35')
E1=$(extents)

# --- live border: the whole derivation follows, extents republished
q 'set-border 4' >/dev/null
wait_for 10 extents_is "4, 4, $((H + 6)), 4"
E2=$(extents)
set -- $(metrics); H2=$1; TOP2=$2; BTN2=$3
D2=$(q 'set t $::frameof([lindex [array names ::frameof] 0])
rz-edge $t 2 8')

# --- reload with an empty config: the stock numbers come back
: > "$CONF/tk9wm.tcl"
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY"
wait_for 10 extents_is "6, 6, $((H + 8)), 6"
E3=$(extents)
wait_for 10 grip_is 24.0
G3=$(grip_len)

kill $CA 2>/dev/null
sleep 0.5
kill $WM 2>/dev/null
sleep 0.5

echo "--- boot: h=$H top=$TOP btn=$BTN extents «$E0» grip $G0 edge(5,35)=$D0"
echo "--- grips 12: grip $G1 edge(5,35)=$D1 extents «$E1»"
echo "--- border 4: h=$H2 top=$TOP2 btn=$BTN2 extents «$E2» edge(2,8)=$D2"
echo "--- reload: extents «$E3» grip $G3"

echo "--- verdict"
if [ "$E0" = "10, 10, $((H + 12)), 10" ]; then
    echo "OK: the config's border answers in the extents"
else
    echo "FAIL: boot extents «$E0», want «10, 10, $((H + 12)), 10»"
fi
if [ "$BTN" = "$((H - 10))" ]; then
    echo "OK: the button size follows the config's border"
else
    echo "FAIL: boot btn=$BTN, want $((H - 10)) (titleh $H - border 10)"
fi
if [ "$G0" = "40.0" ] && [ "$D0" = "nw" ]; then
    echo "OK: the config's grips are drawn and hit-tested at 40"
else
    echo "FAIL: boot grips drawn $G0 (want 40.0), edge(5,35)=$D0 (want nw)"
fi
if [ "$G1" = "12.0" ] && [ "$D1" = "w" ]; then
    echo "OK: a live set-grips repaints and re-hit-tests"
else
    echo "FAIL: after set-grips 12: drawn $G1 (want 12.0), edge(5,35)=$D1 (want w)"
fi
if [ "$E1" = "$E0" ]; then
    echo "OK: a grips change moves no layout (extents untouched)"
else
    echo "FAIL: extents moved on set-grips: «$E1», had «$E0»"
fi
if [ "$E2" = "4, 4, $((H + 6)), 4" ] && [ "$BTN2" = "$((H - 4))" ]; then
    echo "OK: a live set-border re-derives and republishes"
else
    echo "FAIL: after set-border 4: extents «$E2» (want «4, 4, $((H + 6)), 4»), btn=$BTN2 (want $((H - 4)))"
fi
if [ "$D2" = "nw" ]; then
    echo "OK: the corner still answers inside the new thin border"
else
    echo "FAIL: after set-border 4: edge(2,8)=$D2, want nw"
fi
if [ "$E3" = "6, 6, $((H + 8)), 6" ] && [ "$G3" = "24.0" ]; then
    echo "OK: an empty-config reload restores the stock numbers"
else
    echo "FAIL: after reload: extents «$E3» (want «6, 6, $((H + 8)), 6»), grip $G3 (want 24.0)"
fi
if grep -q 'handler error\|soft failure — settle' "$HERE/wm-decorknobs.log"; then
    echo "FAIL: errors in the WM log:"
    grep 'handler error\|soft failure — settle' "$HERE/wm-decorknobs.log"
else
    echo "OK: no handler or settler errors"
fi
check_invariants "$HERE/wm-decorknobs.log"
