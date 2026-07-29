#!/bin/sh
# Regression for the style keys that decide a window's SHAPE: `decor`
# (how much frame it wears) and `place` (the geometry it is born with),
# plus the `style` shorthand inside a panel-button declaration.
#
# The desk carries a panel, so every percentage below is a percentage of
# the WORKAREA and not of the screen — the test reads _NET_WORKAREA off
# the root and computes what it expects from that, which is also a check
# that the two agree.
#
# Actors, in manage order:
#   развёрнутый  place max            — fills the workarea; the max
#                                       button then restores it to the
#                                       geometry it never had (240x120
#                                       at the first cascade slot)
#   уголок       30%bottom,50%right   — and it CLAIMS +500+50, which the
#                                       style must beat
#   полочный     declared by a panel-button's `style` shorthand:
#                {decor none place 50%right} — the right half, no frame
#                at all (frame extents 0)
#   свойразмер   place {right bottom} — sizeless terms: its own size,
#                pinned into the corner
#   безрамочный  decor border         — border and grips, no title strip
#   кривой       place 50%diagonal    — unreadable: logged and dropped,
#                the window still managed and cascaded
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:74
rm -f /tmp/.X74-lock /tmp/.X11-unix/X74
Xvfb :74 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
trap 'kill $XVFB 2>/dev/null; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
panel-button полка {
    match  {filter -title полочный}
    launch {}
    style  {decor none place 50%right}
}
wm-style {filter -title развёрнутый} {place max}
wm-style {filter -title уголок}      {place "30%bottom,50%right"}
wm-style {filter -title свойразмер}  {place {right bottom}}
wm-style {filter -title безрамочный} {decor border}
wm-style {filter -title кривой}      {place 50%diagonal}
EOF
sleep 1

LOG="$HERE/wm-style.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$HERE/wm.tcl" > "$LOG" 2>&1 &
WM=$!
sleep 1.5

for spec in "развёрнутый 240x120" "уголок 240x120+500+50" "полочный 240x120" \
            "свойразмер 240x120" "безрамочный 240x120" "кривой 240x120"; do
    set -- $spec
    "$LINUX/whale" "$HERE/client.tcl" "$1" "$2" "#fce94f" "" "" 25 \
        >> "$HERE/style-client.log" 2>&1 &
    sleep 0.7
done
sleep 2

import -display :74 -window root "$HERE/style-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/style-test.png"

# the ids in manage order, and the desk's own numbers
set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
MAXW=$1; CORNER=$2; SHELF=$3; OWNSZ=$4; BORDERED=$5; BROKEN=$6
eval "$(xprop -root _NET_WORKAREA | sed 's/.*= //; s/,//g' \
        | awk '{print "WAX=" $1 "; WAY=" $2 "; WAW=" $3 "; WAH=" $4}')"
eval "$(sed -n 's/^WM: titlebar h=\([0-9]*\) top=\([0-9]*\) btn=\([0-9]*\).*/TITLEH=\1; TOP=\2; BTN=\3/p' \
        "$LOG" | head -1)"
B=$(xprop -id "$MAXW" _NET_FRAME_EXTENTS | sed 's/.*= //; s/,//g' | awk '{print $1}')

geom() {   # WxH+X+Y of a client's own window, in root coordinates
    xwininfo -id "$1" | awk '/Width:/ {w=$2} /Height:/ {h=$2}
        /Absolute upper-left X/ {x=$NF} /Absolute upper-left Y/ {y=$NF}
        END {print w "x" h "+" x "+" y}'
}
extents() { xprop -id "$1" _NET_FRAME_EXTENTS | sed 's/.*= //; s/,//g'; }
check() {  # label want got
    if [ "$2" = "$3" ]; then echo "OK: $1 — $3"; else
        echo "FAIL: $1 — got $3, want $2"; fi
}

echo "--- workarea ${WAW}x${WAH}+${WAX}+${WAY}, border $B, deco top $TOP"
echo "--- actors: max=$MAXW corner=$CORNER shelf=$SHELF own=$OWNSZ" \
     "bordered=$BORDERED broken=$BROKEN"
echo "--- placement lines:"
grep -E '^WM: (place|frame \.f[0-9]+ for|panel up)' "$LOG"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$BROKEN" ]; then
    echo "FAIL: missing actor ids (got $*)"
fi

check "max fills the workarea" \
    "$((WAW - 2*B))x$((WAH - TOP - B))+$((WAX + B))+$((WAY + TOP))" \
    "$(geom "$MAXW")"

CW=$((WAW / 2)); CH=$((WAH * 30 / 100))
check "30%bottom,50%right beats the client's own +500+50" \
    "$((CW - 2*B))x$((CH - TOP - B))+$((WAX + WAW - CW + B))+$((WAY + WAH - CH + TOP))" \
    "$(geom "$CORNER")"

check "the panel button's style: right half, undecorated" \
    "$((WAW / 2))x${WAH}+$((WAX + WAW - WAW / 2))+${WAY}" \
    "$(geom "$SHELF")"
check "decor none reports no frame extents" "0 0 0 0" "$(extents "$SHELF")"

FW=$((240 + 2*B)); FH=$((120 + TOP + B))
check "sizeless terms keep the size and pin the corner" \
    "240x120+$((WAX + WAW - FW + B))+$((WAY + WAH - FH + TOP))" \
    "$(geom "$OWNSZ")"

check "decor border keeps the border, drops the title strip" \
    "$B $B $B $B" "$(extents "$BORDERED")"
check "the bordered client kept its own size" "240x120" \
    "$(geom "$BORDERED" | sed 's/+.*//')"

if grep -q 'WM: place «50%diagonal».*cannot read term' "$LOG"; then
    echo "OK: the unreadable placement was logged and dropped"
else
    echo "FAIL: no complaint about «50%diagonal»: $(grep 'WM: place' "$LOG")"
fi
check "the client with the broken placement is managed anyway" "240x120" \
    "$(geom "$BROKEN" | sed 's/+.*//')"

# The max button of the maximized frame: last column but one, in the
# title strip. Clicking it RESTORES — to the geometry the window would
# have had without the style, which is what `place max` had to invent.
# The maximized window is the OLDEST, so every later frame stacks above
# it and the right end of its titlebar (where the button lives) is
# covered by the shelf: raise it first with a click on the bare part of
# the strip, which is a raise and nothing else.
xdotool mousemove $((WAX + 200)) $((WAY + B + TITLEH/2)) click 1
sleep 0.4
xdotool mousemove $((WAX + B + (WAW - 2*B) - BTN - BTN/2)) \
                  $((WAY + B + TITLEH/2)) click 1
sleep 0.6
check "the max button restores to the geometry place max saved" \
    "240x120+$((110 + B))+$((80 + TOP))" "$(geom "$MAXW")"

kill $WM 2>/dev/null
pkill -f "$HERE/client.tcl" 2>/dev/null

if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"
fi
