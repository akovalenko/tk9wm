#!/bin/sh
# Regression for the menu-time focus-follows-mouse creep (live report,
# 2026-07-28): while a popup menu holds the keyboard grab, Tk's
# implicit-focus release (the step-32 trap) could park the server focus
# on PointerRoot — and every focus event arrives with mode
# Grab/WhileGrabbed, which the watchdog used to drop wholesale, so the
# display silently switched to focus-follows-mouse and STAYED there
# after the menu closed.
#
# It is now a test of the CURE at its source: the shim refuses Tk the
# two events it arms that machinery with (tkwmx.c, TameImplicitFocus),
# so this scenario — which used to arm the trap on every run — must
# produce no fall at all. The pointer wandering below is what armed it;
# keep it exactly as it is, or the test proves nothing.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-menufocus.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-menufocus.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" \
    > /dev/null 2>&1 &
CA=$!
wait_client "$HERE/wm-menufocus.log" 'жертва'

AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-menufocus.log")
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-menufocus.log" | head -1)
BW=$(sed -n 's/^WM: titlebar h=[0-9]* top=[0-9]* btn=\([0-9]*\).*/\1/p' "$HERE/wm-menufocus.log" | head -1)
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        split(substr($0, RSTART + 1), a, "+")
        print "FX=" a[1] "; FY=" a[2]
    }
}' "$HERE/wm-menufocus.log")"
echo "--- actor: $AID frame at +$FX+$FY top=$TOP btn=$BW"

focusnow() { "$LINUX/whale" "$TOOLS/probe-focus.tcl" \
    | sed -n 's/^PROBE: server focus=\(0x[0-9a-f]*\).*/\1/p'; }

# Arm Tk's trap: put the pointer on the focused client's titlebar —
# the frame's inferior holds the focus, so the crossing carries
# focus=True and Tk marks itself the implicit focus owner.
xdotool mousemove $((FX + 150)) $((FY + 6 + BW / 2))
sleep 0.3
# Open the window-ops menu by its button (the keyboard grab starts).
xdotool mousemove $((FX + 6 + BW / 2)) $((FY + 6 + BW / 2)) click 1
sleep 0.5
# Wander between the menu and the outside world — leaving the armed
# frame is the moment Tk calls XSetInputFocus(PointerRoot).
xdotool mousemove $((FX + 40)) $((FY + TOP + 20))
sleep 0.3
xdotool mousemove 650 450
sleep 0.3
xdotool mousemove $((FX + 40)) $((FY + TOP + 20))
sleep 0.3
DURING=$(focusnow)
xdotool key Escape
sleep 0.5
AFTER=$(focusnow)
kill $WM $CA 2>/dev/null

echo "--- focus during menu: $DURING, after close: $AFTER"
echo "--- verdict"
FAIL=0
if [ "$DURING" = "$AID" ]; then
    echo "OK: focus honest while the menu was open"
elif [ "$DURING" = "0x1" ]; then
    echo "FAIL: focus-follows-mouse while the menu was open (PointerRoot)"; FAIL=1
else
    echo "FAIL: focus during menu is $DURING, want $AID"; FAIL=1
fi
if [ "$AFTER" = "$AID" ]; then
    echo "OK: focus honest after the menu closed"
else
    echo "FAIL: focus after menu is $AFTER, want $AID"; FAIL=1
fi
# Since the shim tames Tk's implicit focus at the source, this scenario
# must not merely SURVIVE the fall — the fall must not happen. The
# assertion is therefore inverted from what it was: it used to demand
# the repair line, proving the watchdog caught the trap; now it demands
# silence, proving the trap was never armed. The repair path itself
# still has a test — run-gareset-test.sh forces PointerRoot from
# OUTSIDE (which no taming can prevent, and which is exactly how a
# stray client causes it) and checks the whole recovery.
if grep -q 'focus fell to PointerRoot' "$HERE/wm-menufocus.log"; then
    echo "FAIL: the display still fell to PointerRoot — Tk's implicit focus is not tamed:"
    grep -c 'focus fell to PointerRoot' "$HERE/wm-menufocus.log" | sed 's/^/    falls: /'
    FAIL=1
else
    echo "OK: no PointerRoot fall at all — the trap was never armed"
fi
if grep -q 'handler error' "$HERE/wm-menufocus.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-menufocus.log"
    FAIL=1
fi
check_invariants "$HERE/wm-menufocus.log"
exit $FAIL
