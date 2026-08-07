#!/bin/sh
# Regression for the titlebar following its FONT, live.
#
# The owner (2026-07-30): a big title font did not change the size of
# the buttons but did change the glyphs inside them — "inconsistent;
# big font should mean big buttons, with big glyphs in them". What it
# turned out to be was worse than inconsistent and only happens on a
# LIVE change: the strip grew, the columns grew with it, and four
# twenty-pixel boxes stayed stranded at the top of a tall titlebar.
# The style bakes the box (glyph plus padding) in at build time, and
# re-creating the photo under its old name does not make treectrl
# re-measure the element that draws it — so the strip is rebuilt when
# the button size changes, the way it already is when the button SET
# does.
#
# Two halves are measured here, and the vacuity run says why: with the
# rebuild backed out the CLICK half still passes — treectrl hit-tests
# the column, which did grow, so the button answers in a place where
# nothing is drawn. That is the owner's "inconsistent" exactly. So the
# pixel is the leg that matters (a point where the box's bottom outline
# can only be if the box grew), and the click is the one that says the
# hit area went with it.
. "$(dirname "$0")/common.sh"
start_xvfb 900x400x24
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT
echo "set-title-font -size 10" > "$CONF/tk9wm.tcl"

LOG="$HERE/wm-titlefont.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM
"$LINUX/whale" "$HERE/client.tcl" "шрифт" 400x120 "#fce94f" "" "" 60 \
    > "$HERE/titlefont-client.log" &
CA=$!
sleep 1.5

metrics() {   # the LAST metrics line — h, top and the button cell
    sed -n 's/^WM: titlebar h=\([0-9]*\) top=\([0-9]*\) btn=\([0-9]*\).*/\1 \2 \3/p' \
        "$LOG" | tail -1
}
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | head -1)
set -- $(metrics); TH0=$1; TOP0=$2; BW0=$3
B=$((TOP0 - TH0 - 2))
echo "--- before: titleh=$TH0 top=$TOP0 btn=$BW0 border=$B"

echo "set-title-font -size 32" > "$CONF/tk9wm.tcl"
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
sleep 2
set -- $(metrics); TH1=$1; TOP1=$2; BW1=$3
echo "--- after:  titleh=$TH1 top=$TOP1 btn=$BW1"
import -display "$DISPLAY" -window root "$HERE/titlefont-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/titlefont-test.png"

# The frame, from the client inside it, at the NEW decoration size.
CX=$(xwininfo -id "$AID" | awk '/Absolute upper-left X/ {print $NF}')
CY=$(xwininfo -id "$AID" | awk '/Absolute upper-left Y/ {print $NF}')
CW=$(xwininfo -id "$AID" | awk '/Width:/ {print $2}')
FX=$((CX - B)); FY=$((CY - TOP1)); FRIGHT=$((CX + CW + B))
# The close button is the rightmost cell; the box is pinned to the top
# of the strip (the slack goes south), so its bottom outline lies one
# pixel above strip_top + btn — which at the OLD size is bare titlebar.
BOXX=$((FRIGHT - B - BW1 / 2))
pixel() { import -window root png:- 2>/dev/null \
    | convert png:- -format "%[pixel:p{$1,$2}]" info:-; }
EDGE_NEW=$(pixel $BOXX $((FY + B + BW1 - 1)))
EDGE_OLD=$(pixel $BOXX $((FY + B + BW0 - 1)))
echo "--- pixels: at the new box's bottom edge $EDGE_NEW, at the old one $EDGE_OLD"

# ...and it must ANSWER there too: the middle of the new close cell.
xdotool mousemove $BOXX $((FY + B + BW1 / 2)) click 1
sleep 1

kill $WM $CA 2>/dev/null

echo "--- verdict"
FAIL=0
if [ "$TH1" -gt "$TH0" ] && [ "$BW1" -gt "$BW0" ]; then
    echo "OK: the strip and the button cell both grew ($TH0/$BW0 -> $TH1/$BW1)"
else
    echo "FAIL: metrics did not follow the font ($TH0/$BW0 -> $TH1/$BW1)"; FAIL=1
fi
if [ "$EDGE_NEW" = "srgb(255,255,255)" ]; then
    echo "OK: the box is DRAWN at the new size — its outline is where only a\
 grown box can put it"
else
    echo "FAIL: nothing white at the new box's bottom edge ($EDGE_NEW) — the\
 button stayed the size it was built at"; FAIL=1
fi
if grep -q "got WM_DELETE_WINDOW" "$HERE/titlefont-client.log"; then
    echo "OK: ...and it ANSWERS at the new size, the middle of the new cell"
else
    echo "FAIL: a click in the middle of the new close cell did nothing"; FAIL=1
fi
if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"; FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
