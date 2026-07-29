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
export DISPLAY=:59
rm -f /tmp/.X59-lock /tmp/.X11-unix/X59
Xvfb :59 -screen 0 800x600x24 >/dev/null 2>&1 &
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
client_size() {
    xwininfo -id "$VID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}'
}
client_center() {   # in root coordinates
    cx=$(xwininfo -id "$VID" | awk '/Absolute upper-left X/ {print $NF}')
    cy=$(xwininfo -id "$VID" | awk '/Absolute upper-left Y/ {print $NF}')
    cw=$(xwininfo -id "$VID" | awk '/Width:/ {print $2; exit}')
    ch=$(xwininfo -id "$VID" | awk '/Height:/ {print $2; exit}')
    echo "$((cx + cw / 2)) $((cy + ch / 2))"
}
client_east_mid() { # 4 px inside the east edge, half way down
    cx=$(xwininfo -id "$VID" | awk '/Absolute upper-left X/ {print $NF}')
    cy=$(xwininfo -id "$VID" | awk '/Absolute upper-left Y/ {print $NF}')
    cw=$(xwininfo -id "$VID" | awk '/Width:/ {print $2; exit}')
    ch=$(xwininfo -id "$VID" | awk '/Height:/ {print $2; exit}')
    echo "$((cx + cw - 4)) $((cy + ch / 2))"
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

# ---- the same nine digits in RESIZE, where they name HANDLES ----
key alt+space; key s              # keyboard RESIZE; the default handle is se
G0=$(frame_at); S0=$(client_size)
set -- $(client_center); CPIX=$(pixel "$1" "$2")   # cell 5 is not a handle
import -window root "$HERE/compass-handles.png" 2>/dev/null \
    && echo "DRIVER: screenshot (the handles) -> $HERE/compass-handles.png"
# A point inside cell 6, where the east edge is NOW. The compass is a
# keymap and not a decoration of the edges: pull the east edge in and
# the digits must stay where they were drawn.
set -- $(client_east_mid); EX=$1; EY=$2
E0=$(pixel "$EX" "$EY")
key Left; key Left; key Left; key Left      # se handle: the east edge in 40
E1=$(pixel "$EX" "$EY")
key Right; key Right; key Right; key Right  # ...and back to 300x200
key KP_Home                       # numpad 7 — drag by the nw corner now
key Right; key Right; key Down    # ...which SHRINKS, and the frame follows
G1=$(frame_at); S1=$(client_size)
key Up                            # the north edge back up 10: 190 -> 200
key KP_Up                         # numpad 8 — the north edge alone
key Right; key Right              # ...which has no horizontal freedom
G2=$(frame_at); S2=$(client_size)
key Escape                        # both the size AND the position come back
G3=$(frame_at); S3=$(client_size)

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

gx() { echo "$1" | sed 's/^+\([-0-9]*\)+.*/\1/'; }
gy() { echo "$1" | sed 's/^+[-0-9]*+\([-0-9]*\)$/\1/'; }
X0=$(gx "$G0"); Y0=$(gy "$G0")
expect "the mode starts on the se handle, as it always did" \
    "1" "$(grep -c 'resize .* by the se handle' "$HERE/wm-compass.log")"
expect "7 took the nw handle" \
    "1" "$(grep -c 'compass .*: by the nw handle' "$HERE/wm-compass.log")"
expect "...and dragging it right and down shrank the window" "280x190" "$S1"
expect "...with the frame following, so the far corner stayed put" \
    "+$((X0 + 20))+$((Y0 + 10))" "$G1"
expect "8 took the north edge, which has no horizontal freedom" \
    "280x200" "$S2"
expect "...so a horizontal arrow moved nothing" "+$((X0 + 20))+$Y0" "$G2"
expect "Escape put the size back" "$S0" "$S3"
expect "...and the position a west/north handle had moved" "$G0" "$G3"
if [ "$E0" = "$AMBER" ] && [ "$E1" = "$AMBER" ]; then
    echo "OK: the digits stayed put while the edge they marked moved off"
else
    echo "FAIL: cell 6 followed the east edge (before=$E0 after=$E1,\
 wanted $AMBER both times)"
fi
if [ "$CPIX" != "$AMBER" ] && [ "$CPIX" != "srgb(224,169,74)" ]; then
    echo "OK: 5 names no edge, so it is no handle and is not drawn ($CPIX)"
else
    echo "FAIL: a cell was drawn in the middle of the resize compass ($CPIX)"
fi

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
check_invariants "$HERE/wm-compass.log"
