#!/bin/sh
# Regression for the numpad compass in keyboard MOVE: the nine digits
# stick the frame to an edge, a corner or the center of the workarea,
# size untouched.
#
# What is measured, in order:
#   - a jump is a STEP and not a verdict — Escape after one still
#     restores the geometry the mode started on;
#   - 0 goes back to that geometry without leaving the mode, and Enter
#     after a jump commits where the jump put it;
#   - the compass is DEGENERATE arithmetic and not a state flag: a
#     window that fills the workarea gets no compass at all (its nine
#     cells would be one point), a full-width one gets the three
#     vertical cells and not the six that would sit on top of them.
#
# Actors:
#   A (жертва)   300x200, cascaded to +110+80 — the ordinary window
#   B (широкое)  styled `place {100%left 30%top}` — full width, short
. "$(dirname "$0")/common.sh"
export DISPLAY=:96
rm -f /tmp/.X96-lock /tmp/.X11-unix/X96
Xvfb :96 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/compass-config"
mkdir -p "$HERE/compass-config"
cat > "$HERE/compass-config/tk9wm.tcl" <<'EOF'
wm-style {filter -title "широкое"} {place {100%left 30%top}}
EOF

XDG_CONFIG_HOME="$HERE/compass-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-compass.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" "" "" 60 &
CA=$!
sleep 1

key() { xdotool key "$@"; sleep 0.4; }
# One pixel off the root, as ImageMagick names colors: srgb(r,g,b).
pixel() {
    import -window root png:- 2>/dev/null \
        | convert png:- -format "%[pixel:p{$1,$2}]" info:-
}
AMBER="srgb(193,125,17)"      # KBMR_BG — the mode's color, and the compass's

VID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-compass.log" | head -1)
# The decoration, from the WM's own metrics line: the top strip is
# given, the border falls out of decotop = border + titleh + 2. With
# them the FRAME's position is what xwininfo says about the client,
# less the decoration it sits behind.
TITLEH=$(sed -n 's/^WM: titlebar h=\([0-9]*\) top=.*/\1/p' "$HERE/wm-compass.log" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-compass.log" | head -1)
B=$((TOP - TITLEH - 2))
FW=$((300 + 2 * B))
FH=$((200 + TOP + B))
frame_at() {
    cx=$(xwininfo -id "$VID" | awk '/Absolute upper-left X/ {print $NF}')
    cy=$(xwininfo -id "$VID" | awk '/Absolute upper-left Y/ {print $NF}')
    echo "+$((cx - B))+$((cy - TOP))"
}

key alt+space; key m          # keyboard MOVE on A
import -window root "$HERE/compass-mode.png" 2>/dev/null \
    && echo "DRIVER: screenshot (the compass) -> $HERE/compass-mode.png"
key KP_Home;  AT7=$(frame_at)     # numpad 7 — the workarea's top-left
key KP_Next;  AT3=$(frame_at)     # numpad 3 — bottom-right
key KP_Begin; AT5=$(frame_at)     # numpad 5 — centered
key Escape;   ATESC=$(frame_at)   # ...and none of that committed

key alt+space; key m
key KP_End                        # numpad 1 — bottom-left
key 0;        AT0=$(frame_at)     # the way back, mode still running
key KP_Prior                      # numpad 9 — top-right
key Return;   ATDONE=$(frame_at)  # committed where the jump put it

key alt+space; key x              # Maximize
sleep 0.5
key alt+space; key m
MAXPIX=$(pixel 400 300)           # dead center: A's client, if no compass
import -window root "$HERE/compass-max.png" 2>/dev/null \
    && echo "DRIVER: screenshot (maximized: no compass) -> $HERE/compass-max.png"
key Escape

# B: full width, short — only the vertical cells have anywhere to go
"$LINUX/whale" "$HERE/client.tcl" "широкое" 300x200 "#8ae234" "" "" 20 &
CB=$!
sleep 1.5
key alt+space; key m
WIDECENTER=$(pixel 400 300)       # cell 5 — drawn (amber box, white digit)
WIDELEFT=$(pixel 10 300)          # cell 4 — nowhere to go, not drawn
import -window root "$HERE/compass-wide.png" 2>/dev/null \
    && echo "DRIVER: screenshot (full width: 8/5/2 only) -> $HERE/compass-wide.png"
key Escape

kill $WM $CA $CB 2>/dev/null

echo "--- actor: A=$VID (deco top=$TOP border=$B, frame ${FW}x${FH})"
echo "--- keyboard lines:"
grep -E 'keyboard (move|resize)|compass|place 0x' "$HERE/wm-compass.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-compass.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
expect() {   # what where got
    if [ "$2" = "$3" ]; then
        echo "OK: $1 ($3)"
    else
        echo "FAIL: $1 — wanted $2, got $3"
    fi
}
expect "7 stuck the frame to the top-left corner"  "+0+0"   "$AT7"
expect "3 stuck it to the bottom-right corner" \
    "+$((800 - FW))+$((600 - FH))" "$AT3"
expect "5 centered it" \
    "+$(((800 - FW) / 2))+$(((600 - FH) / 2))" "$AT5"
expect "Escape after the jumps restored the entry geometry" "+110+80" "$ATESC"
expect "0 went back to the entry geometry, mode still running" "+110+80" "$AT0"
expect "Enter committed where 9 put it" "+$((800 - FW))+0" "$ATDONE"

if [ "$MAXPIX" = "$AMBER" ]; then
    echo "FAIL: a maximized window got a compass — every cell the same point"
else
    echo "OK: a window filling the workarea gets no compass ($MAXPIX at the center)"
fi
if grep -q 'compass .*: nothing to offer' "$HERE/wm-compass.log"; then
    echo "OK: ...and said so"
else
    echo "FAIL: the empty compass was not accounted for in the log"
fi
# The cell is an amber box with a WHITE digit centered in it, and the
# center pixel is whichever the font makes it — either says "drawn".
if [ "$WIDECENTER" = "$AMBER" ] || [ "$WIDECENTER" = "srgb(255,255,255)" ]; then
    if [ "$WIDELEFT" != "$AMBER" ]; then
        echo "OK: a full-width window gets the vertical cells and not the rest"
    else
        echo "FAIL: a full-width window drew cell 4, which has nowhere to go"
    fi
else
    echo "FAIL: a full-width window drew no cell 5 (center=$WIDECENTER)"
fi
if grep -q 'compass .*: cells 8 5 2' "$HERE/wm-compass.log"; then
    echo "OK: ...and named them"
else
    echo "FAIL: the short compass was not accounted for in the log"
fi
