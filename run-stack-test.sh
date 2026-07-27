#!/bin/sh
# Regression for glued transient stacking (fvwm's RaiseTransient +
# StackTransientParent, on by default there): raising ANY member of a
# window's transient group must raise the group, with the transients
# above their leader. Scenario: leader A with a transient dialog D,
# bystander B. Click B (plain raise), then click A's body — D must end
# up ABOVE A (the old code raised A alone and buried the dialog), and
# the whole group above B. Then click D — the group must stay glued.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:76
rm -f /tmp/.X76-lock /tmp/.X11-unix/X76
Xvfb :76 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-stack.log" 2>&1 &
WM=$!
sleep 1.5

# leader 300x200 (dialog 220x140 pops after 2 s and stays), then a bystander
"$LINUX/whale" "$HERE/client-dlg.tcl" 300x200 220x140 \
    > "$HERE/stack-leader.log" &
CA=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "сосед" 240x120 "#8ae234" \
    > "$HERE/stack-b.log" &
CB=$!
sleep 2.5

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
"$LINUX/whale-cli" "$HERE/probe-stack.tcl" :76 > "$HERE/stack-probe1.log"
click $((FX3 + 110)) $((FY3 + 84))      # D: the group stays glued
"$LINUX/whale-cli" "$HERE/probe-stack.tcl" :76 > "$HERE/stack-probe2.log"

kill $WM $CA $CB 2>/dev/null

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
