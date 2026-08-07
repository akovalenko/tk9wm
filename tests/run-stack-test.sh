#!/bin/sh
# Regression for glued transient stacking (fvwm's RaiseTransient +
# StackTransientParent, on by default there): raising ANY member of a
# window's transient group must raise the group, with the transients
# above their leader. Scenario: leader A with a transient dialog D,
# bystander B. Click B (plain raise), then click A's body — D must end
# up ABOVE A (the old code raised A alone and buried the dialog), and
# the whole group above B. Then click D — the group must stay glued.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-stack.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-stack.log" $WM

# leader 300x200 (dialog 220x140 pops after 2 s and stays), then a
# bystander. Both live 30 s: the bury pass at the end needs every actor
# still on the desk, and a client that quietly ran out of time turns a
# measurement into a coincidence (this pass first "passed" against a
# leader that had already exited).
"$LINUX/whale" "$HERE/client-dlg.tcl" 300x200 220x140 30 \
    > "$HERE/stack-leader.log" &
CA=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "сосед" 240x120 "#8ae234" "" "" 30 \
    > "$HERE/stack-b.log" &
CB=$!
wait_client "$HERE/wm-stack.log" 'сосед'
# ...and the dialog the leader pops on its own 2 s timer — the manage
# roster below counts on all three being in
wait_client "$HERE/wm-stack.log" 'диалог'

# Actors by manage order: A (leader), B, D (dialog). Frame positions from
# the WM's own log; the click offsets below are chosen so each click
# lands on the intended window's BODY given the sizes above (A's far
# left edge below B/D, B's far right edge beyond D, D's center on top).
set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-stack.log")
AID=$1; BID=$2; DID=$3
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        n++; split(substr($0, RSTART + 1), a, "+")
        print "FX" n "=" a[1] "; FY" n "=" a[2]
    }
}' "$HERE/wm-stack.log")"
echo "--- actors: A=$AID@+$FX1+$FY1 B=$BID@+$FX2+$FY2 D=$DID@+$FX3+$FY3"

click() { xdotool mousemove "$1" "$2" click 1; sleep 0.4; }
click $((FX2 + 220)) $((FY2 + 50))      # B: plain raise
click $((FX1 + 10))  $((FY1 + 215))     # A: must pull D above itself
"$LINUX/whale-cli" "$TOOLS/probe-stack.tcl" "$DISPLAY" > "$HERE/stack-probe1.log"
click $((FX3 + 110)) $((FY3 + 84))      # D: the group stays glued
"$LINUX/whale-cli" "$TOOLS/probe-stack.tcl" "$DISPLAY" > "$HERE/stack-probe2.log"

# --- bury. A fourth window C, planted in the far corner where it
# touches NOTHING (its own +x+y is a position claim, so the WM puts it
# exactly there instead of cascading it into the pile). Started last so
# the three frames the clicks above are aimed at keep their numbering.
#
# C is what makes the pass discriminating. Raise C, then re-raise the
# group over it, then bury: the topmost OTHER window is now C, but the
# window the group was actually covering is B. Focusing the topmost
# would be the easy rule and the wrong one — a window that never shared
# a pixel with the buried group was not underneath it.
"$LINUX/whale" "$HERE/client.tcl" "далёкий" 200x110+560+430 "#ad7fa8" \
    "" "" 30 > "$HERE/stack-c.log" &
CC=$!
wait_client "$HERE/wm-stack.log" 'далёкий'
CID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-stack.log" | sed -n 4p)
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        n++; split(substr($0, RSTART + 1), a, "+")
        if (n == 4) print "FX4=" a[1] "; FY4=" a[2]
    }
}' "$HERE/wm-stack.log")"
echo "--- C=$CID@+$FX4+$FY4 (must touch nothing)"
click $((FX4 + 100)) $((FY4 + 80))      # C to the top, and focused
click $((FX3 + 110)) $((FY3 + 84))      # ...and the group back over it
xdotool key alt+space; sleep 0.5
xdotool key b; sleep 0.8
"$LINUX/whale-cli" "$TOOLS/probe-stack.tcl" "$DISPLAY" > "$HERE/stack-probe3.log"
BURIED=$(grep -c '^WM: buried' "$HERE/wm-stack.log")
FOCUS_AFTER=$(sed -n 's/^WM: focus -> \(0x[0-9a-f]*\).*/\1/p' \
    "$HERE/wm-stack.log" | tail -1)

kill $WM $CA $CB $CC 2>/dev/null

rank() { grep -nE "(^| )$2( |\$)" "$1" | head -1 | cut -d: -f1; }
verdict() {
    RA=$(rank "$1" "$AID"); RB=$(rank "$1" "$BID"); RD=$(rank "$1" "$DID")
    if [ -z "$RA" ] || [ -z "$RB" ] || [ -z "$RD" ]; then
        echo "FAIL($2): actor missing from the stack (A=$RA B=$RB D=$RD)"
    elif [ "$RB" -lt "$RA" ] && [ "$RA" -lt "$RD" ]; then
        echo "OK($2): bottom -> top is B < A(leader) < D(dialog)"
    else
        echo "FAIL($2): bottom -> top ranks A=$RA B=$RB D=$RD, want B < A < D"
    fi
}
echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-stack.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
verdict "$HERE/stack-probe1.log" "click on leader"
verdict "$HERE/stack-probe2.log" "click on dialog"

echo "--- after bury: focus=$FOCUS_AFTER (B=$BID, the far C=$CID), $BURIED bury line(s)"
RA=$(rank "$HERE/stack-probe3.log" "$AID")
RB=$(rank "$HERE/stack-probe3.log" "$BID")
RD=$(rank "$HERE/stack-probe3.log" "$DID")
if [ "$BURIED" = 1 ]; then
    echo "OK(bury): the ops menu's b reached bury-group"
else
    echo "FAIL(bury): $BURIED bury lines in the log, want 1"
fi
if [ -n "$RA" ] && [ -n "$RB" ] && [ -n "$RD" ] \
        && [ "$RA" -lt "$RB" ] && [ "$RD" -lt "$RB" ]; then
    echo "OK(bury): the whole group went under B (ranks A=$RA D=$RD B=$RB)"
else
    echo "FAIL(bury): ranks A=$RA D=$RD B=$RB, want the group below B"
fi
if [ "$FOCUS_AFTER" = "$BID" ]; then
    echo "OK(bury): ...and the focus went to B — what the group COVERED, not the topmost C"
elif [ "$FOCUS_AFTER" = "$CID" ]; then
    echo "FAIL(bury): focus went to C, the topmost — but C was never under the group"
else
    echo "FAIL(bury): focus is «$FOCUS_AFTER», want B «$BID»"
fi
