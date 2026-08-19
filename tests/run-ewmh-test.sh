#!/bin/sh
# Regression for the OUTWARD half of EWMH: what a client learns about
# the desk rather than about itself. A pager, wmctrl, xdotool and every
# toolkit that places a popup "somewhere sensible" (fcitx included)
# read these, and until they existed every such client had to guess.
#
# The list came from a diff against fvwm3's root window, so the test
# checks the same things a client would: the client list in arrival
# order, the stacking list bottom-to-top (which must follow a raise),
# the workarea shrinking under a panel, and the one-desktop statement.
#
# ...and the one message that comes back the other way for the same
# audience: _NET_CLOSE_WINDOW, how a pager or a taskbar closes a
# window it does not own.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/ewmh-config"
mkdir -p "$HERE/ewmh-config"
cat > "$HERE/ewmh-config/tk9wm.tcl" <<'EOF'
action терм {}
panel-button терм
EOF

XDG_CONFIG_HOME="$HERE/ewmh-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-ewmh.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-ewmh.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "первый" 240x120 "#8ae234" "" "" 30 \
    > "$HERE/ewmh-a.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-ewmh.log" 'первый'
"$LINUX/whale" "$HERE/client.tcl" "второй" 240x120 "#729fcf" "" "" 30 \
    > "$HERE/ewmh-b.log" 2>&1 &
CB=$!
wait_client "$HERE/wm-ewmh.log" 'второй'

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-ewmh.log")
AID=$1; BID=$2
# xprop spells a WINDOW list "…(WINDOW): window id # 0x1, 0x2" and a
# CARDINAL one "…(CARDINAL) = 1, 2" — strip whichever lead-in came
prop() { xprop -root "$1" 2>/dev/null | sed -e 's/.*# //' -e 's/.*= //'; }
LIST=$(prop _NET_CLIENT_LIST)
STACK=$(prop _NET_CLIENT_LIST_STACKING)
WORK=$(prop _NET_WORKAREA)
NDESK=$(prop _NET_NUMBER_OF_DESKTOPS)
GEOM=$(prop _NET_DESKTOP_GEOMETRY)
VIEW=$(prop _NET_DESKTOP_VIEWPORT)
ADESK=$(xprop -id "$AID" _NET_WM_DESKTOP 2>/dev/null | sed 's/.*= //')
STRUT=$(xprop -id "$AID" _KDE_NET_WM_FRAME_STRUT 2>/dev/null | sed 's/.*= //')

# Raise the FIRST client: the stacking list must follow, the arrival
# list must not. The click lands in A's BODY, in the strip B's frame
# does not cover — a titlebar click there would have hit the ops-menu
# button and opened a menu instead (measured, and it is why this
# comment names a coordinate).
xdotool mousemove 140 200 click 1
sleep 0.7
STACK2=$(prop _NET_CLIENT_LIST_STACKING)
LIST2=$(prop _NET_CLIENT_LIST)

# --- the one INWARD message this suite owns: _NET_CLOSE_WINDOW, which
# is how everything outside the desk closes a window — a pager, a
# taskbar, `wmctrl -c`. It is sent to the ROOT and names the client, so
# it needs a branch of its own; without one it went nowhere at all, not
# even a line in the log, and the window stood (the owner, 2026-08-19).
SUPPORTS_CLOSE=$(xprop -root _NET_SUPPORTED | tr ',' '\n' | grep -c _NET_CLOSE_WINDOW)
wmctrl -i -c "$BID"
sleep 1
LISTC=$(prop _NET_CLIENT_LIST)

kill $CA $CB 2>/dev/null
sleep 0.7
LIST3=$(prop _NET_CLIENT_LIST)
kill $WM 2>/dev/null
sleep 0.5

PH=$(sed -n 's/^WM: panel [^ ]* up (1 buttons, \([0-9]*\) px.*/\1/p' "$HERE/wm-ewmh.log" | tail -1)
echo "--- A=$AID B=$BID panel=${PH}px"
echo "--- list=«$LIST» stacking=«$STACK» -> after raise «$STACK2»"
echo "--- workarea=«$WORK» geometry=«$GEOM» viewport=«$VIEW» desktops=$NDESK"
echo "--- A: _NET_WM_DESKTOP=«$ADESK» _KDE_NET_WM_FRAME_STRUT=«$STRUT»"

echo "--- verdict"
if [ "$LIST" = "$AID, $BID" ]; then
    echo "OK: the client list is in arrival order"
else
    echo "FAIL: client list «$LIST», want «$AID, $BID»"
fi
if [ "$STACK" = "$AID, $BID" ]; then
    echo "OK: the stacking list starts bottom-to-top with B on top"
else
    echo "FAIL: stacking «$STACK», want «$AID, $BID»"
fi
if [ "$STACK2" = "$BID, $AID" ]; then
    echo "OK: raising A moved it to the top of the stacking list"
else
    echo "FAIL: after the raise stacking is «$STACK2», want «$BID, $AID»"
fi
if [ "$LIST2" = "$LIST" ]; then
    echo "OK: ...and the arrival list did not move"
else
    echo "FAIL: the arrival list changed on a raise: «$LIST2»"
fi
if [ "$WORK" = "0, 0, 800, $((600 - PH))" ]; then
    echo "OK: the workarea stops above the panel ($WORK)"
else
    echo "FAIL: workarea «$WORK», want «0, 0, 800, $((600 - PH))»"
fi
if [ "$GEOM" = "800, 600" ] && [ "$VIEW" = "0, 0" ] && [ "$NDESK" = "1" ]; then
    echo "OK: one desktop, stated rather than left to guess"
else
    echo "FAIL: geometry «$GEOM» viewport «$VIEW» desktops «$NDESK»"
fi
if [ "$ADESK" = "0" ] && [ -n "$STRUT" ]; then
    echo "OK: a managed window carries its desktop and the KDE strut ($STRUT)"
else
    echo "FAIL: desktop «$ADESK», strut «$STRUT»"
fi
if [ "$SUPPORTS_CLOSE" = 1 ]; then
    echo "OK: _NET_CLOSE_WINDOW is advertised — a pager will use it"
else
    echo "FAIL: _NET_CLOSE_WINDOW is not in _NET_SUPPORTED"
fi
if grep -q 'got WM_DELETE_WINDOW' "$HERE/ewmh-b.log"; then
    echo "OK: a close asked from outside the desk reached the client politely"
else
    echo "FAIL: wmctrl -c on B never became a WM_DELETE_WINDOW"
fi
if [ "$LISTC" = "$AID" ]; then
    echo "OK: ...and the closed window left the client list ($LISTC)"
else
    echo "FAIL: after the outside close the list is «$LISTC», want «$AID»"
fi
if [ -z "$LIST3" ]; then
    echo "OK: the list empties when the clients go"
else
    echo "FAIL: dead clients still listed: «$LIST3»"
fi
if grep -q 'handler error' "$HERE/wm-ewmh.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-ewmh.log"
fi
