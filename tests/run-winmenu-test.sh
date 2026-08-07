#!/bin/sh
# The window menu as a MOUSE menu: where it lands, and the drag that
# picks from it.
#
#  - a gesture on the strip puts the menu under the hand — the
#    pointer's x, the strip's bottom edge for the y (it drops out of
#    the bar, leaving the title readable above it);
#  - the same menu called up by <Alt>space has no hand and stays at the
#    window's own top-left corner, where it always was;
#  - press, drag onto an entry, release: the entry fires. The events
#    for it never reach the menu on their own (Tk sends everything to
#    the widget the press happened on while a button is down), so this
#    leg is the whole of what the hand-over is for;
#  - press and release IN PLACE picks nothing and leaves the menu
#    standing — it still holds the keyboard, so its hotkey fires;
#  - drag INTO the menu and release outside it is "never mind": the
#    menu is gone and nothing fired.
#
# The menu's geometry is read off the WM's own log line and the row
# height derived from it; nothing about the popup is hardcoded here.
. "$(dirname "$0")/common.sh"
start_xvfb

CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT
: > "$CONF/tk9wm.tcl"   ;# the stock desk: title <3> opens the ops menu

LOG="$HERE/wm-winmenu.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

"$LINUX/whale" "$HERE/client.tcl" "меню" 300x200 "#729fcf" "" "" 90 \
    > "$HERE/winmenu-client.log" &
CA=$!
wait_client "$LOG" 'меню'

AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
TH=$(sed -n 's/^WM: titlebar h=\([0-9]*\) .*/\1/p' "$LOG" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$LOG" | head -1)
BORDER=$((TOP - TH - 2))   ;# decotop = border + h + 2, the WM's own sum
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        split(substr($0, RSTART + 1), a, "+")
        print "FX=" a[1] "; FY=" a[2]
    }
}' "$LOG")"
BY=$((FY + BORDER + TH / 2))       ;# the middle of the strip
HITX=$((FX + 180))                 ;# a spot on it, well right of the buttons
echo "--- actor: $AID frame at +$FX+$FY, border $BORDER, titlebar h=$TH top=$TOP"

# The last menu the WM put up: WxH+X+Y off its own open line.
menu_geom() { sed -n 's/^WM: winops open 0x[0-9a-f]* //p' "$LOG" | tail -1; }
fires() { grep -c '^WM: winops 0x[0-9a-f]* ' "$LOG"; }

# --- 1: button 3 on the strip — under the hand, below the bar
xdotool mousemove $HITX $BY click 3
sleep 0.6
GEOM1=$(menu_geom)
xdotool key Escape
sleep 0.4

# --- 2: <Alt>space — no hand, so the window's corner
xdotool mousemove 700 500      ;# pointer parked far away, to be ignored
xdotool key --clearmodifiers alt+space
sleep 0.6
GEOM2=$(menu_geom)
xdotool key Escape
sleep 0.4

# --- 3: press, drag onto an entry, release. Row 7 of the fourteen is
#        Raise — harmless, and the menu logs the pick by name.
xdotool mousemove $HITX $BY mousedown 3
sleep 0.5
GEOM3=$(menu_geom)
MW=${GEOM3%%x*}; REST=${GEOM3#*x}
MH=${REST%%+*}; REST=${REST#*+}
MX=${REST%%+*}; MY=${REST#*+}
ROWH=$(((MH - 2) / 14))   ;# the ops menu has fourteen rows
ROW7=$((MY + 1 + 6 * ROWH + ROWH / 2))
echo "--- menu $GEOM3, row height $ROWH, Raise at $((MX + MW / 2)),$ROW7"
xdotool mousemove $((MX + MW / 2)) $((MY + 1 + ROWH / 2))   ;# through row 1...
sleep 0.3
xdotool mousemove $((MX + MW / 2)) $ROW7                    ;# ...down to row 7
sleep 0.3
xdotool mouseup 3
sleep 0.6
DRAGGED=$(sed -n 's/^WM: winops 0x[0-9a-f]* //p' "$LOG" | tail -1)
AFTER3=$(fires)

# --- 4: press and release in place — nothing picked, menu left standing.
#        Its hotkey proves it is still up and still holds the keyboard.
xdotool mousemove $HITX $BY mousedown 3
sleep 0.4
xdotool mouseup 3
sleep 0.5
STUCK=$(fires)
xdotool key r
sleep 0.5
BYKEY=$(sed -n 's/^WM: winops 0x[0-9a-f]* //p' "$LOG" | tail -1)
AFTER4=$(fires)

# --- 5: into the menu and out again — never mind. Nothing fires, and
#        the menu is gone: the hotkey that worked in leg 4 does nothing.
xdotool mousemove $HITX $BY mousedown 3
sleep 0.4
GEOM5=$(menu_geom)
MY5=${GEOM5##*+}
xdotool mousemove $((HITX + 20)) $((MY5 + 3 * ROWH))   ;# inside the menu
sleep 0.3
xdotool mousemove $((HITX + 400)) $((MY5 + 3 * ROWH))  ;# and out to its right
sleep 0.3
xdotool mouseup 3
sleep 0.5
AFTER5=$(fires)
xdotool key r
sleep 0.5
AFTER5K=$(fires)

# --- 6: the MENU BUTTON on the strip, clicked twice at DIFFERENT
#        pixels of it. A button is a place of its own: the menu must
#        hang from the button, so both presses put it in the same spot
#        (the owner, 2026-08-04 — it used to follow the pointer and
#        wander by a few pixels per press).
BTNMID=$((FY + BORDER + TH / 2))
xdotool mousemove $((FX + BORDER + 3)) $BTNMID click 1
sleep 0.6
GEOM6a=$(menu_geom)
xdotool key Escape
sleep 0.4
xdotool mousemove $((FX + BORDER + 14)) $((BTNMID + 3)) click 1
sleep 0.6
GEOM6b=$(menu_geom)
xdotool key Escape
sleep 0.4

kill $WM $CA 2>/dev/null

echo "--- verdict"
FAIL=0
WANT1x=$HITX
WANT1y=$((FY + TOP))
case "$GEOM1" in
    *+$WANT1x+$WANT1y) echo "OK: the strip's menu opened at the pointer's x,\
 under the bar ($GEOM1)" ;;
    *) echo "FAIL: menu at «$GEOM1», want +$WANT1x+$WANT1y"; FAIL=1 ;;
esac
WANT2x=$((FX + BORDER))
case "$GEOM2" in
    *+$WANT2x+$WANT1y) echo "OK: <Alt>space kept the window's corner ($GEOM2)" ;;
    *) echo "FAIL: the keyboard's menu is at «$GEOM2», want +$WANT2x+$WANT1y"
       FAIL=1 ;;
esac
if [ "$DRAGGED" = "Raise" ] && [ "$AFTER3" = 1 ]; then
    echo "OK: press-drag-release fired the row it was released on (Raise)"
else
    echo "FAIL: the drag fired «$DRAGGED» ($AFTER3 picks in the run, want 1)"
    FAIL=1
fi
if [ "$STUCK" = "$AFTER3" ]; then
    echo "OK: a press and release in place picked nothing"
else
    echo "FAIL: the release in place fired something ($AFTER3 -> $STUCK)"; FAIL=1
fi
if [ "$BYKEY" = "Raise" ] && [ "$AFTER4" = $((STUCK + 1)) ]; then
    echo "OK: ...and left the menu standing — its hotkey still fires"
else
    echo "FAIL: the menu left standing did not answer its hotkey\
 (last «$BYKEY», $STUCK -> $AFTER4)"; FAIL=1
fi
if [ "$AFTER5" = "$AFTER4" ] && [ "$AFTER5K" = "$AFTER4" ]; then
    echo "OK: in and out again picked nothing and dismissed the menu"
else
    echo "FAIL: the in-and-out drag left something behind\
 ($AFTER4 -> $AFTER5 -> $AFTER5K)"; FAIL=1
fi
# The button's menu: same spot both presses, and that spot is the
# button's own left edge — the frame's corner, since the menu button is
# the first column — under the bar, exactly where <Alt>space puts it.
if [ "$GEOM6a" = "$GEOM6b" ]; then
    echo "OK: the button's menu lands in the same place however it is hit ($GEOM6a)"
else
    echo "FAIL: the button's menu followed the pointer ($GEOM6a vs $GEOM6b)"
    FAIL=1
fi
case "$GEOM6a" in
    *+$WANT2x+$WANT1y) echo "OK: ...aligned under the button, like <Alt>space" ;;
    *) echo "FAIL: the button's menu is at «$GEOM6a», want +$WANT2x+$WANT1y"
       FAIL=1 ;;
esac
check_invariants "$LOG" || FAIL=1
if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"
    FAIL=1
fi
exit $FAIL
