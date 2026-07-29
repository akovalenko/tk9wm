#!/bin/sh
# Regression for how a window is CARRIED, and for the one clamp on a
# position we otherwise honor verbatim. Three subjects, all the owner's
# (2026-07-30):
#
#   - the SLOP: a title press is a click until the pointer has moved a
#     few pixels, so aiming at a titlebar to raise a window does not
#     nudge it on the way;
#   - EDGE RESISTANCE: a carried window sticks to an edge of the
#     workarea, so flush-against-the-panel is a position one can hit;
#   - a USPosition claim off the top of the screen (Qt Creator asks for
#     +0-2) is honored in spirit and clamped to the screen, since a
#     titlebar above the top edge is nobody's intent.
#
# The desk carries a panel on the LEFT, which is what makes the two
# rectangles differ: the workarea starts at x=WAX, the screen at 0.
# Resistance is about the first, the USPosition clamp about the second.
. "$(dirname "$0")/common.sh"
export DISPLAY=:56
rm -f /tmp/.X56-lock /tmp/.X11-unix/X56
Xvfb :56 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
trap 'kill $XVFB 2>/dev/null; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
panel dock {
    set-panel-side left
    panel-button полка {}
}
EOF
sleep 1

LOG="$HERE/wm-carry.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5

# A: the carried one. B: the one that asks for +0-2, like Qt Creator.
"$LINUX/whale" "$HERE/client.tcl" "ноша" 300x200 "#fce94f" "" "" 60 &
CA=$!
sleep 1.2
# +0+-2, not +0-2: in an X geometry a bare -2 counts from the far edge,
# and what Qt Creator actually asks for is the coordinate minus two.
"$LINUX/whale" "$HERE/client.tcl" "выскочка" 240x120+0+-2 "#8ae234" "" "" 60 &
CB=$!
sleep 1.5

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
AID=$1; BID=$2
eval "$(sed -n 's/^WM: titlebar h=\([0-9]*\) top=\([0-9]*\).*/TITLEH=\1; TOP=\2/p' \
        "$LOG" | head -1)"
B=$((TOP - TITLEH - 2))
eval "$(xprop -root _NET_WORKAREA | sed 's/.*= //; s/,//g' \
        | awk '{print "WAX=" $1 "; WAY=" $2 "; WAW=" $3 "; WAH=" $4}')"

frame_at() {   # +X+Y of a client's FRAME
    x=$(xwininfo -id "$1" | awk '/Absolute upper-left X/ {print $NF}')
    y=$(xwininfo -id "$1" | awk '/Absolute upper-left Y/ {print $NF}')
    echo "+$((x - B))+$((y - TOP))"
}
gx() { echo "$1" | sed 's/^+\([-0-9]*\)+.*/\1/'; }
gy() { echo "$1" | sed 's/^+[-0-9]*+\([-0-9]*\)$/\1/'; }
# Press on A's titlebar, well clear of any button, and drag by (dx,dy)
# in two steps — a single jump would be one motion event, and the slop
# is about the travel between them.
title_drag() {
    dx=$1; dy=$2
    ax=$(xwininfo -id "$AID" | awk '/Absolute upper-left X/ {print $NF}')
    ay=$(xwininfo -id "$AID" | awk '/Absolute upper-left Y/ {print $NF}')
    px=$((ax + 120)); py=$((ay - TOP + B + 6))
    xdotool mousemove $px $py mousedown 1
    xdotool mousemove $((px + dx / 2)) $((py + dy / 2))
    xdotool mousemove $((px + dx)) $((py + dy)) mouseup 1
    sleep 0.5
}

G0=$(frame_at "$AID"); GX0=$(gx "$G0"); GY0=$(gy "$G0")
G_B=$(frame_at "$BID")   ;# B is never carried; read it while it is up

# 1. a two-pixel wobble is a CLICK: the window must not have moved
title_drag 2 2
G_SLOP=$(frame_at "$AID")

# 2. a real drag carries — and by the FULL travel, the slop included:
#    the window catches up so the grabbed spot stays under the pointer
title_drag 60 40
G_CARRY=$(frame_at "$AID")

# 3. resistance: aim 5 px short of the workarea's left edge and land ON
#    it instead
title_drag $((WAX + 5 - GX0 - 60)) 0
G_STICK=$(frame_at "$AID")

# 4. ...and past the resistance it lets go: 30 px inside is 30 px inside
title_drag 30 0
G_FREE=$(frame_at "$AID")

import -window root "$HERE/carry-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/carry-test.png"
kill $WM $CA $CB 2>/dev/null

echo "--- workarea ${WAW}x${WAH}+${WAX}+${WAY}, border $B, deco top $TOP"
echo "--- A=$AID at $G0; B=$BID"
echo "--- frame lines:"
grep -E '^WM: frame \.f[0-9]+ for' "$LOG"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
expect() {   # what wanted got
    if [ "$2" = "$3" ]; then
        echo "OK: $1 ($3)"
    else
        echo "FAIL: $1 — wanted $2, got $3"
    fi
}
expect "a two-pixel wobble on the titlebar is a click, not a carry" \
    "$G0" "$G_SLOP"
expect "a real drag carries by the whole travel, slop included" \
    "+$((GX0 + 60))+$((GY0 + 40))" "$G_CARRY"
expect "aimed 5 px inside the workarea's left edge, it stuck to the edge" \
    "+$WAX+$((GY0 + 40))" "$G_STICK"
expect "...and 30 px inside — past the resistance — is 30 px inside" \
    "+$((WAX + 30))+$((GY0 + 40))" "$G_FREE"
expect "the +0+-2 claim kept its x and was clamped onto the screen in y" \
    "+0+0" "$G_B"
expect "...and was NOT pushed into the workarea: the panel may overlap it" \
    "0" "$(gx "$G_B")"
check_invariants "$LOG"
