#!/bin/sh
# Regression: THE DOUBLED OPENER GOES THROUGH (set-key-double-pass) —
# screen/tmux's C-a C-a, spoken by a sequence.
#
# A second press of the chord that opened a sequence — the prefix at
# depth one, the help chord on its root — is answered with a replay:
# the active grab falls, the server reprocesses the press past root's
# passive grabs, and the chord lands in the focused window natively,
# modifiers intact. The whole sequence runs under a SYNC active grab
# for it (every press, release and repeat frozen for its one answer),
# and detectable autorepeat is what tells a held prefix from a second
# press.
#
# Asserted, in order:
#  - a doubled prefix forwards ONE chord to the witness, modifier
#    intact (state 64), and the sequence is gone — the next bare key
#    types straight into the client;
#  - the ordinary walk still works under the sync discipline, fast
#    (--delay 0: the frozen queue holds the race closed) and slow;
#  - an explicit bind of the doubled chord beats the forward (the
#    keyecho invariant, read from the doubling side);
#  - a restart re-arms the opener: prefix, other prefix, other prefix
#    again = the second one forwarded;
#  - the help opener obeys the same rule: doubled, its chord reaches
#    the witness and the sequence (box and all) is gone;
#  - a HELD prefix does not spray: autorepeat presses are the hold,
#    the sequence stands, and the first press after the release
#    forwards exactly once;
#  - set-key-double-pass off restores the restart of old.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/keydouble-config"
mkdir -p "$HERE/keydouble-config"
cat > "$HERE/keydouble-config/tk9wm.tcl" <<'EOF'
set-welcome off
wm-bind {<Super>d w} {puts "WM: the desk ran d w"} deep-w
wm-bind {<Super>e <Super>e} {puts "WM: the desk ran the explicit double"} expl-dbl
EOF

XDG_CONFIG_HOME="$HERE/keydouble-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-keydouble.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-keydouble.log" $WM

q() { printf '%s\n' "$1" > "$HERE/keydouble-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/keydouble-config/q.tcl"; }

"$LINUX/whale" "$HERE/client-press.tcl" doubwit 240x120 "#729fcf" 90 \
    > "$HERE/keydouble-witness.log" 2>&1 &
WIT=$!
wait_client "$HERE/wm-keydouble.log" doubwit

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-keydouble.log")
WID=$1
focused_is() { [ "$(q 'format 0x%x $::focused')" = "$1" ]; }
xdotool search --name doubwit windowfocus
wait_for 5 focused_is "$WID" || echo "note: the WM never took doubwit for the focus"

key() { xdotool key "$@"; sleep 0.5; }
saidc() { grep -c "$1" "$HERE/wm-keydouble.log" || true; }
heard() { grep -c "$1" "$HERE/keydouble-witness.log" || true; }

DAR=$(saidc 'detectable autorepeat refused')
[ "$DAR" = 0 ] || echo "note: the server refused detectable autorepeat — forwards will not arm"

# ---- the doubled prefix forwards, once, modifier intact ----
key super+d
key super+d
DBL_D1=$(saidc 'key Super+d -> doubled, passed to the window')
FWD_D1=$(heard 'key d state 64')
key w
WNAT=$(heard 'key w state 0')
RAN_DW0=$(saidc 'the desk ran d w')
SEQGONE1=$(q 'list [expr {$::keyseq eq ""}] [expr {!$::kbd_grabbed}]')

# ---- the ordinary walk still works: slow, then the frozen queue ----
key super+d
key w
RAN_DW1=$(saidc 'the desk ran d w')
xdotool key --delay 0 super+d w
sleep 0.7
RAN_DW2=$(saidc 'the desk ran d w')
WLEAK=$(heard 'key w state')

# ---- an explicit bind of the doubled chord beats the forward ----
key super+e
key super+e
RAN_EE=$(saidc 'the desk ran the explicit double')
DBL_E=$(saidc 'key Super+e -> doubled')
ELEAK=$(heard 'key e state')

# ---- a restart re-arms the opener ----
key super+d
key super+t
RESTART_T=$(saidc 'key Super+t restarts the sequence')
key super+t
DBL_T=$(saidc 'key Super+t -> doubled, passed to the window')
FWD_T=$(heard 'key t state 64')

# ---- the help opener, doubled, hands its chord over ----
key super+h
HELP1=$(saidc 'key help from the top')
key super+h
DBL_H=$(saidc 'key Super+h -> doubled, passed to the window')
FWD_H=$(heard 'key h state 64')
SEQGONE2=$(q 'list [expr {$::keyseq eq ""}] [expr {!$::kbd_grabbed}]')

# ---- a held prefix is a hold, not a stream of doubles ----
# (autorepeat presses land at depth one and are swallowed; whether the
# server repeats an XTEST-held key or not, the assertions catch a
# spray if one fires and the stand if none does)
xdotool keydown super+d
sleep 1.2
xdotool keyup d
xdotool keyup super
sleep 0.5
STANDS=$(q 'expr {$::keyseq ne ""}')
DBL_DH=$(saidc 'key Super+d -> doubled, passed to the window')
FWD_DH=$(heard 'key d state 64')
RESTART_D=$(saidc 'key Super+d restarts the sequence')
key super+d
DBL_D2=$(saidc 'key Super+d -> doubled, passed to the window')
FWD_D2=$(heard 'key d state 64')

# ---- the knob: off = the restart of old ----
q 'set-key-double-pass off' >/dev/null
key super+d
key super+d
RESTART_OFF=$(saidc 'key Super+d restarts the sequence')
FWD_OFF=$(heard 'key d state 64')
key Escape
ABORTS=$(saidc 'key sequence abort')

kill $WIT $WM 2>/dev/null
sleep 0.5

echo "--- doubled/restart lines:"
grep -E 'doubled|restarts the sequence|help from the top|ran d w|explicit double|sequence abort|autorepeat' \
    "$HERE/wm-keydouble.log"
echo "--- verdict"
if [ "$DBL_D1" = 1 ] && [ "$FWD_D1" = 1 ] && [ "$WNAT" = 1 ] \
        && [ "$RAN_DW0" = 0 ] && [ "$SEQGONE1" = "1 1" ]; then
    echo "OK: the doubled prefix forwarded once, modifier intact, and the sequence was gone"
else
    echo "FAIL: doubled prefix (line=$DBL_D1 fwd=$FWD_D1 wnat=$WNAT dw=$RAN_DW0 gone=$SEQGONE1)"
fi
if [ "$RAN_DW1" = 1 ] && [ "$RAN_DW2" = 2 ] && [ "$WLEAK" = 1 ]; then
    echo "OK: the ordinary walk answers, slow and with no delay, and no inner key leaked"
else
    echo "FAIL: the walk (slow=$RAN_DW1 fast=$RAN_DW2 wleak=$WLEAK, want 1/2/1)"
fi
if [ "$RAN_EE" = 1 ] && [ "$DBL_E" = 0 ] && [ "$ELEAK" = 0 ]; then
    echo "OK: the explicit doubled bind kept its word over the forward"
else
    echo "FAIL: explicit double (ran=$RAN_EE dbl=$DBL_E leak=$ELEAK)"
fi
if [ "$RESTART_T" = 1 ] && [ "$DBL_T" = 1 ] && [ "$FWD_T" = 1 ]; then
    echo "OK: the restart re-armed the opener and the restarted prefix doubled"
else
    echo "FAIL: restart re-arm (restart=$RESTART_T dbl=$DBL_T fwd=$FWD_T)"
fi
if [ "$HELP1" -ge 1 ] && [ "$DBL_H" = 1 ] && [ "$FWD_H" = 1 ] \
        && [ "$SEQGONE2" = "1 1" ]; then
    echo "OK: the help opener doubled its chord into the witness and left"
else
    echo "FAIL: help doubled (open=$HELP1 dbl=$DBL_H fwd=$FWD_H gone=$SEQGONE2)"
fi
if [ "$STANDS" = 1 ] && [ "$DBL_DH" = "$DBL_D1" ] && [ "$FWD_DH" = "$FWD_D1" ] \
        && [ "$RESTART_D" = 0 ] && [ "$DBL_D2" = 2 ] && [ "$FWD_D2" = 2 ]; then
    echo "OK: the held prefix stood still, and the press after the release forwarded once"
else
    echo "FAIL: the hold (stands=$STANDS dblheld=$DBL_DH fwdheld=$FWD_DH restarts=$RESTART_D dbl2=$DBL_D2 fwd2=$FWD_D2)"
fi
if [ "$RESTART_OFF" = 1 ] && [ "$FWD_OFF" = 2 ] && [ "$ABORTS" -ge 1 ]; then
    echo "OK: with the knob off the second press restarts, as of old"
else
    echo "FAIL: knob off (restart=$RESTART_OFF fwd=$FWD_OFF aborts=$ABORTS)"
fi
