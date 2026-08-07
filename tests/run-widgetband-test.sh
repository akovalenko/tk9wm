#!/bin/sh
# Regression for WHAT THE STRIP TELLS THE TYPE — `-band` and `-across`
# (the owner, 2026-08-02), measured on the clock, which is their worked
# example.
#
# The claim under test is one sentence: THE SAME DECLARATION comes out
# a different shape in a different place, and the widget still does not
# know where it lives. Four placements, and the clock has to read each
# one right:
#
#  - on a HORIZONTAL strip the thickness is height, so the two lines go
#    SIDE BY SIDE and the strip does not have to grow to hold a stack;
#  - on the DESK nothing is scarce, so they stack, which is also what
#    it looked like everywhere before any of this;
#  - on a VERTICAL strip whose buttons are broad, the width is ALREADY
#    PAID FOR — so the row is free there and is taken. This is the case
#    that makes -across worth having: "always grow along the band"
#    would squeeze the clock into one line for nothing;
#  - on a vertical strip that is NARROW, nothing is paid and the stack
#    — the narrow shape — comes back.
#
# The shapes are read off the WM's own area line rather than off pixels
# because it is the geometry that is the claim; the drawn colour is
# run-widget-test's business.
. "$(dirname "$0")/common.sh"
start_xvfb 900x500x24
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT

LOG="$HERE/wm-widgetband.log"
CLOCK='wm-widget clock -type clock -background #4e9a06'

# A config, then a reload, then the area it produced — the whole loop.
conf() { cat > "$CONF/tk9wm.tcl"; }
reload() {
    "$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
    sleep 1.5
}
# The last area's WxH, as two numbers.
geo() { sed -n 's/^WM: widget area \([0-9]*\)x\([0-9]*\)+.*/\1 \2/p' "$LOG" \
        | tail -1; }
# ...and how THICK the strip ended up, which the panel says in so many
# words — not to be read off its WxH, where the thickness is the height
# of a bottom bar and the width of a side one.
band() { sed -n 's/^WM: panel default up ([0-9]* buttons, \([0-9]*\) px,.*/\1/p'\
         "$LOG" | tail -1; }

conf <<EOF
set-welcome off
action терминал { launch {exec xterm &} }
panel-button терминал
$CLOCK -on {panel default}
EOF
sleep 1
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 2.5
BOTTOM=$(geo)
BOTTOMBAND=$(band)

conf <<EOF
set-welcome off
action терминал { launch {exec xterm &} }
panel-button терминал
$CLOCK -on screen -place {left top}
EOF
reload
DESK=$(geo)

# A vertical panel BROAD BY ITS BUTTONS: a long label lying across a
# side strip is exactly the case the first approximation got wrong.
conf <<EOF
set-welcome off
set-panel-side left
action длинная-кнопка-терминала { launch {exec xterm &} }
panel-button длинная-кнопка-терминала
$CLOCK -on {panel default}
EOF
reload
WIDE=$(geo)
WIDEBAND=$(band)

conf <<EOF
set-welcome off
set-panel-side left
action т { launch {exec xterm &} }
panel-button т
$CLOCK -on {panel default}
EOF
reload
NARROW=$(geo)
NARROWBAND=$(band)

import -display "$DISPLAY" -window root "$HERE/widgetband-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/widgetband-test.png"
kill $WM 2>/dev/null

echo "--- areas:"
grep -E '^WM: widget area ' "$LOG"
echo "--- bottom panel: $BOTTOM (band ${BOTTOMBAND}px)   desk: $DESK"
echo "--- left panel, broad buttons: $WIDE (band ${WIDEBAND}px)\
   narrow: $NARROW (band ${NARROWBAND}px)"

echo "--- verdict"
FAIL=0
# NOT read off the aspect ratio: the stacked clock is wider than it is
# tall as well (a big bold time over a small date), so there is no
# threshold that names the two shapes. They are named by comparing the
# SAME clock in the two places — which is what the test claims anyway.
STACKW=$(echo "$DESK" | sed 's/ .*//');  STACKH=$(echo "$DESK" | sed 's/.* //')
ROWW=$(echo "$BOTTOM" | sed 's/ .*//'); ROWH=$(echo "$BOTTOM" | sed 's/.* //')
if [ "$ROWW" -gt "$STACKW" ] && [ "$ROWH" -lt "$STACKH" ]; then
    echo "OK: the same declaration is wider and shallower on a horizontal strip\
 than on the desk (${DESK} -> ${BOTTOM}) — the row, and it was told nothing but\
 which way the strip runs"
else
    echo "FAIL: on the desk ${DESK} and on a bottom panel ${BOTTOM} — the clock\
 laid out the same in both, so -band bought nothing"; FAIL=1
fi
same() {
    if [ "$2" = "$3" ]; then
        echo "OK: $1 ($2)"
    else
        echo "FAIL: $1 — got $2, wanted $3"; FAIL=1
    fi
}
same "a broad vertical strip spends the width its buttons already paid for,\
 and the clock comes out the same row as on a bottom bar" "$WIDE" "$BOTTOM"
same "...and on a narrow one nothing is paid, so the stack comes back" \
    "$NARROW" "$DESK"

# The point of the row on a bottom panel is the thickness it SAVES: the
# strip must not have grown to what a stack would have needed, which is
# what the desk's own stack measures for us.
if [ -n "$BOTTOMBAND" ] && [ "$BOTTOMBAND" -lt "$STACKH" ]; then
    echo "OK: ...and the bottom strip stayed ${BOTTOMBAND}px instead of growing\
 to the ${STACKH}px a stack wants — the saving is the whole point"
else
    echo "FAIL: the bottom strip is ${BOTTOMBAND}px and a stack wants\
 ${STACKH}px — the row saved nothing"; FAIL=1
fi
# ...and the mirror image: the broad side strip must not have grown for
# the clock at all. STRICTLY wider than the clock's own claim, which is
# what proves the buttons paid for it — a strip merely as wide as the
# widget could be one the widget itself widened.
WIDEW=$(echo "$WIDE" | sed 's/ .*//')
if [ -n "$WIDEBAND" ] && [ "$WIDEBAND" -gt "$((WIDEW + 2))" ]; then
    echo "OK: ...and the broad side strip was ${WIDEBAND}px before the clock\
 asked for ${WIDEW} — the row went into thickness somebody else bought"
else
    echo "FAIL: the side strip is ${WIDEBAND}px and the clock wanted ${WIDEW} —\
 it took the row and paid for the width itself"; FAIL=1
fi
if grep -qE 'build failed|handler error' "$LOG"; then
    echo "FAIL: errors in the log:"; grep -E 'build failed|handler error' "$LOG"
    FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
