#!/bin/sh
# Regression for the menu-time focus-follows-mouse creep (live report,
# 2026-07-28): while a popup menu holds the keyboard grab, Tk's
# implicit-focus release (the step-32 trap) can still park the server
# focus on PointerRoot — and every focus event arrives with mode
# Grab/WhileGrabbed, which the watchdog used to drop wholesale, so the
# display silently switched to focus-follows-mouse and STAYED there
# after the menu closed. The WM must see the PointerRoot fall and
# repair it even while its own keyboard grab is active.
. "$(dirname "$0")/common.sh"
export DISPLAY=:89
rm -f /tmp/.X89-lock /tmp/.X11-unix/X89
Xvfb :89 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-menufocus.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" \
    > /dev/null 2>&1 &
CA=$!
sleep 1.5

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
if grep -q 'focus fell to PointerRoot' "$HERE/wm-menufocus.log"; then
    echo "OK: the watchdog saw the PointerRoot fall (the trap did fire)"
else
    echo "FAIL: no PointerRoot repair in the log — the scenario never armed the trap"
    FAIL=1
fi
if grep -q 'handler error' "$HERE/wm-menufocus.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-menufocus.log"
    FAIL=1
fi
exit $FAIL
