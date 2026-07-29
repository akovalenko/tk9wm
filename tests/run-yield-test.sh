#!/bin/sh
# Regression for how a `place` rule YIELDS to a window's own -geometry,
# aspect by aspect. The owner's report (2026-07-30): his xterm rule is
# `place 50%bottom,80%left` with no `force`, and `xterm -geometry 20x20`
# came up placed exactly like a bare xterm — the 20x20 thrown away.
#
# Because -geometry is TWO claims, separately flagged, and this is what
# xterm actually sets (measured the same day):
#
#   -geometry 20x20          USSize     and no USPosition
#   -geometry 20x20+300+200  both
#   (nothing)                neither — only the P forms
#
# The cast is MIXED, and each half is here because the other cannot do
# its job. Tk's `wm geometry` sets USPosition and never USSize, so a Tk
# client cannot claim a size at all; and xterm stamps USSize whenever
# `-geometry` is present, size in it or not — `-geometry +300+200`
# claims both (measured), so an xterm cannot claim a position alone.
# Hence xterms for the size cases and a Tk client for the position one.
#
# The expectations are RELATIONAL for the same reason they have to be:
# an xterm's size is its font's business and its increments snap
# whatever we ask for. So a sixth actor runs the same `-geometry 20x20`
# with a title no rule matches, and is the reference for "the size it
# would have had anyway" — which is the owner's own comparison.
. "$(dirname "$0")/common.sh"
export DISPLAY=:54
rm -f /tmp/.X54-lock /tmp/.X11-unix/X54
Xvfb :54 -screen 0 1000x700x24 >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
trap 'kill $XVFB 2>/dev/null; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
wm-style {filter -title {proba-*}} {place 50%bottom,80%left}
wm-style {filter -title upryamec} {place {50%bottom 80%left force}}
EOF
sleep 1

LOG="$HERE/wm-yield.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5

term() { xterm -T "$1" ${2:+-geometry} $2 -e sleep 60 >/dev/null 2>&1 & sleep 1.2; }
term proba-size  20x20
# The position-only claimant, which has to be a Tk client — see above.
# It asks for +100+200 and not +300+200 like the rest: the rule sizes
# it to 80% of the workarea, and at x=300 that would hang off the right
# edge and be clamped, which is a different leg's business.
"$LINUX/whale" "$HERE/client.tcl" "proba-place" +100+200 "#8ae234" "" "" 60 &
sleep 1.2
term proba-both  20x20+300+200
term proba-mute
term upryamec    20x20+300+200
term reference   20x20          # no rule matches this one
sleep 1.5

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
SIZE=$1; POS=$2; BOTH=$3; MUTE=$4; FORCED=$5; REF=$6
eval "$(sed -n 's/^WM: titlebar h=\([0-9]*\) top=\([0-9]*\).*/TITLEH=\1; TOP=\2/p' \
        "$LOG" | head -1)"
B=$((TOP - TITLEH - 2))
eval "$(xprop -root _NET_WORKAREA | sed 's/.*= //; s/,//g' \
        | awk '{print "WAX=" $1 "; WAY=" $2 "; WAW=" $3 "; WAH=" $4}')"

geom() {
    xwininfo -id "$1" | awk '/Width:/ {w=$2} /Height:/ {h=$2}
        /Absolute upper-left X/ {x=$NF} /Absolute upper-left Y/ {y=$NF}
        END {print w "x" h "+" x "+" y}'
}
size() { geom "$1" | sed 's/+.*//'; }
at()   { geom "$1" | sed 's/^[0-9]*x[0-9]*//'; }
# The bottom edge of a client's FRAME, which is what a `bottom` pull
# puts flush against the workarea — size-independent, so it survives
# whatever the font does to an xterm.
bottom() {
    xwininfo -id "$1" | awk -v b="$B" '/Height:/ {h=$2}
        /Absolute upper-left Y/ {y=$NF} END {print y + h + b}'
}
left() {
    xwininfo -id "$1" | awk -v b="$B" '/Absolute upper-left X/ {print $NF - b}'
}

import -window root "$HERE/yield-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/yield-test.png"
S_SIZE=$(size "$SIZE");   A_SIZE=$(at "$SIZE")
S_POS=$(size "$POS");     A_POS=$(at "$POS")
S_BOTH=$(size "$BOTH");   A_BOTH=$(at "$BOTH")
S_MUTE=$(size "$MUTE");   A_MUTE=$(at "$MUTE")
S_FORCED=$(size "$FORCED"); A_FORCED=$(at "$FORCED")
S_REF=$(size "$REF")
L_SIZE=$(left "$SIZE"); BT_SIZE=$(bottom "$SIZE")
kill $WM 2>/dev/null

echo "--- workarea ${WAW}x${WAH}+${WAX}+${WAY}, border $B, deco top $TOP"
echo "--- actors: size=$SIZE place=$POS both=$BOTH mute=$MUTE" \
     "forced=$FORCED ref=$REF"
echo "--- placement lines:"
grep -E '^WM: (place|0x[0-9a-f]+ claims)' "$LOG"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$REF" ]; then
    echo "FAIL: missing actor ids (got $*)"
fi
expect() {   # what wanted got
    if [ "$2" = "$3" ]; then
        echo "OK: $1 ($3)"
    else
        echo "FAIL: $1 — wanted $2, got $3"
    fi
}
# what the rule does when it gets its way, in x only (the y and the
# sizes are the font's business)
expect "a window that said nothing is sized and placed by the rule" \
    "+$((WAX + B))" "$(echo "$A_MUTE" | sed 's/+[0-9-]*$//')"

expect "one that said HOW BIG keeps the size it would have had anyway" \
    "$S_REF" "$S_SIZE"
expect "...and the rule still pulls it, flush left" "$WAX" "$L_SIZE"
expect "...and flush to the bottom" "$((WAY + WAH))" "$BT_SIZE"

# the Tk client's increment is the degenerate 1x1, so the rule's size
# lands on it exactly and can be predicted outright
expect "one that said WHERE is sized by the rule" \
    "$((WAW * 80 / 100 - 2*B))x$((WAH * 50 / 100 - TOP - B))" "$S_POS"
expect "...and keeps its own place" "+$((100 + B))+$((200 + TOP))" "$A_POS"

expect "one that said BOTH keeps its size" "$S_REF" "$S_BOTH"
expect "...and its place" "+$((300 + B))+$((200 + TOP))" "$A_BOTH"

expect "...unless the rule says force: then the size is the rule's" \
    "$S_MUTE" "$S_FORCED"
expect "...and so is the place" "$A_MUTE" "$A_FORCED"
check_invariants "$LOG"
