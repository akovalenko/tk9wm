#!/bin/sh
# Regression for MODAL INTERLEAVINGS — a modal thing running when
# something that knows nothing about it happens. The owner's report
# (2026-07-29): start a keyboard resize, open the window menu with the
# mouse, pick Maximize; the menu took the key router out from under the
# mode, and the mode was left standing with its amber frame and its
# compass and nothing to answer its keys.
#
# What is measured is not just that one pair. The WM checks its own
# modal invariants and complains in the log — "WM: INVARIANT …" — so
# every leg here asserts BOTH the behaviour it drove and the absence of
# any complaint, and so can every other test in the suite
# (check_invariants in common.sh).
. "$(dirname "$0")/common.sh"
export DISPLAY=:58
rm -f /tmp/.X58-lock /tmp/.X11-unix/X58
Xvfb :58 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

LOG="$HERE/wm-modes.log"
"$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" "" "" 120 &
CA=$!
sleep 1.5

VID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | head -1)
TITLEH=$(sed -n 's/^WM: titlebar h=\([0-9]*\) top=.*/\1/p' "$LOG" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$LOG" | head -1)
BTN=$(sed -n 's/^WM: titlebar .* btn=\([0-9]*\) .*/\1/p' "$LOG" | head -1)
B=$((TOP - TITLEH - 2))

key() { xdotool key "$@"; sleep 0.4; }
geom() {
    xwininfo -id "$VID" | awk '
        /Absolute upper-left X/ {x=$NF} /Absolute upper-left Y/ {y=$NF}
        /Width:/ {w=$2} /Height:/ {h=$2}
        END {print w "x" h "+" (x - '"$B"') "+" (y - '"$TOP"')}'
}
# The MENU button: a btn-square flush against the frame's top-left
# corner. A mouse path — which is the whole point, since the keyboard
# is grabbed by the mode we are interrupting and no chord can fire.
menu_button() {
    fx=$(xwininfo -id "$VID" | awk '/Absolute upper-left X/ {print $NF - '"$B"'}')
    fy=$(xwininfo -id "$VID" | awk '/Absolute upper-left Y/ {print $NF - '"$TOP"'}')
    xdotool mousemove $((fx + B + BTN / 2)) $((fy + B + BTN / 2)) click 1
    sleep 0.5
}

G0=$(geom)

# --- 1. keyboard RESIZE, interrupted by the window menu -> Maximize
key alt+space; key s
menu_button
key x
MAXED=$(geom)

key alt+space; key x          # back down, and back to where we started
sleep 0.5
G_BACK=$(geom)

# --- 2. keyboard MOVE, interrupted by the menu, which is then dismissed
key alt+space; key m
key Right; key Right          # ...after the mode had already moved it
menu_button
key Escape                    # dismiss the menu
G_DISMISS=$(geom)

# --- 3. keyboard MOVE, interrupted by the window DYING under it
key alt+space; key m
kill $CA 2>/dev/null
sleep 1
# ...and the keyboard must not be left grabbed: a fresh window still
# answers the chord that opens its menu.
"$LINUX/whale" "$HERE/client.tcl" "второй" 240x120 "#8ae234" "" "" 30 &
CB=$!
sleep 1.5
key alt+space
key Escape
sleep 0.5

import -window root "$HERE/modes-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/modes-test.png"
kill $WM $CB 2>/dev/null

echo "--- modal lines:"
grep -E 'keyboard (move|resize)|winops|INVARIANT|handover|mode dropped' "$LOG"

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
expect "the menu over a keyboard resize maximized the window" \
    "788x560+0+0" "$MAXED"
expect "...and the mode it interrupted was cancelled, not left running" \
    "2" "$(grep -c 'keyboard \(move\|resize\) .* cancelled' "$LOG")"
expect "...so the un-maximize came back to the size the mode started on" \
    "$G0" "$G_BACK"
expect "a dismissed menu leaves the move it interrupted cancelled too" \
    "$G0" "$G_DISMISS"
expect "a window dying under a keyboard mode drops the mode" \
    "1" "$(grep -c 'keyboard mode dropped' "$LOG")"
expect "...and did not take the keyboard with it — the next chord opened" \
    "1" "$(sed -n '/keyboard mode dropped/,$p' "$LOG" | grep -c 'winops open')"
check_invariants "$LOG"
