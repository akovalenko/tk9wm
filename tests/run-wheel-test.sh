#!/bin/sh
# Regression: a WHEEL scroll inside a client must not freeze the desk.
#
# The trap this measures belongs to running on Tk's own connection. Tk
# rewrites a press of buttons 4-7 into its own MouseWheelEvent BEFORE
# the generic handlers run, and drops the matching release entirely
# (tkEvent.c) — so a wheel press caught by an AnyButton SYNC grab woke
# the dispatcher not at all, no XAllowEvents ever answered it, and the
# pointer stayed frozen for the whole session. Keyboard kept working,
# which is what made it read as "clicks focus the wrong window"; the
# client's own grabs began failing with "another application has grab"
# (owner's report on the Tk widget demo, 2026-07-28).
#
# So: scroll inside the client, then ask a second client whether anyone
# holds the pointer. And check the ordinary click still focuses, since
# the cure was to grab buttons 1-3 instead of all of them.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-wheel.log" 2>&1 &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" "колесо" 300x200 "#ad7fa8" "" "" 25 \
    > "$HERE/wheel-client.log" 2>&1 &
sleep 2.5

# well inside the client area of the first cascade slot (+116+114)
xdotool mousemove 200 180
echo "--- before:"
"$LINUX/whale-cli" "$TOOLS/probe-pointer.tcl" "$DISPLAY" | tee "$HERE/wheel-before.log"
xdotool click 5
sleep 1
echo "--- after a wheel scroll inside the client:"
"$LINUX/whale-cli" "$TOOLS/probe-pointer.tcl" "$DISPLAY" | tee "$HERE/wheel-after.log"
xdotool click 1
sleep 1
echo "--- after an ordinary click inside the client:"
"$LINUX/whale-cli" "$TOOLS/probe-pointer.tcl" "$DISPLAY" | tee "$HERE/wheel-click.log"

kill $WM 2>/dev/null
echo "--- verdict"
if grep -q GrabSuccess "$HERE/wheel-before.log"; then
    echo "OK: the desk started with nobody grabbing"
else
    echo "FAIL: something already held the pointer before the test began"
fi
if grep -q GrabSuccess "$HERE/wheel-after.log"; then
    echo "OK: the wheel scroll left the pointer free"
else
    echo "FAIL: the wheel scroll froze the pointer — the desk is dead"
fi
if grep -q GrabSuccess "$HERE/wheel-click.log"; then
    echo "OK: the ordinary click answered its own grab too"
else
    echo "FAIL: an ordinary click left the pointer frozen"
fi
if grep -q 'focus -> ' "$HERE/wm-wheel.log"; then
    echo "OK: click-to-focus still works with the narrowed grab"
else
    echo "FAIL: nothing was ever focused — the button grab stopped firing"
fi
