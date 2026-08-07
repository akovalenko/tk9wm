#!/bin/sh
# Regression for the titlebar in its three layers: what the strip IS,
# which buttons it wears, and what a gesture on one of them does.
#
#  - maximize toggles to the workarea and back (fvwm semantics —
#    restore returns the saved geometry), close delivers a polite
#    WM_DELETE_WINDOW;
#  - MINIMIZE, the fourth button, iconifies — and is absent from a
#    window whose style refuses to be minimized, a button that could
#    only refuse being worse than no button;
#  - the STRIP itself answers gestures too: a double click maximizes,
#    button 3 opens the ops menu;
#  - and a CONFIG can say all three kinds of thing — declare a button
#    with its own glyph, bind a gesture to a window command, and put
#    Destroy on button 3 of the close box (the sharp edge that is
#    deliberately not a default).
#
# Button geometry is derived from the metrics the WM prints (h/top
# font-driven, btn grip-driven), nothing is hardcoded; the columns are
# counted from the RIGHT edge, which is the order the catalogue
# declares them in.
. "$(dirname "$0")/common.sh"
start_xvfb

CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
# layer 2: one more button, with a picture of its own...
titlebar-button shade -side left -glyph {<svg
 xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path
 d="M3.5 4 L12.5 4" stroke="#ffffff" stroke-width="1.6"
 stroke-linecap="round" fill="none"/></svg>}
# ...layer 3: and what pressing it does, said separately.
titlebar-bind shade <1> Lower
# The owner's own example of what this layer must be able to express,
# and the reason it is not a default: a slip of the right button on the
# close box kills the client outright.
titlebar-bind close <3> Destroy
# A window that refuses to be minimized is not given the button.
wm-style {filter -title стойкое} {minimize refuse}
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$HERE/wm-button.log" 2>&1 &
WM=$!
sleep 1.5

# the empty args skip resizeto/minsize; 90 s outlives every leg below
# (the stock 8 s died just before the close leg and read as a bug)
"$LINUX/whale" "$HERE/client.tcl" "кнопки" 300x200 "#fce94f" "" "" 90 \
    > "$HERE/button-client.log" &
CA=$!
sleep 1.5

AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-button.log")
TH=$(sed -n 's/^WM: titlebar h=\([0-9]*\) .*/\1/p' "$HERE/wm-button.log" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-button.log" | head -1)
BW=$(sed -n 's/^WM: titlebar h=[0-9]* top=[0-9]* btn=\([0-9]*\).*/\1/p' "$HERE/wm-button.log" | head -1)
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        split(substr($0, RSTART + 1), a, "+")
        print "FX=" a[1] "; FY=" a[2]
    }
}' "$HERE/wm-button.log")"
BY=$((FY + 6 + BW / 2))
echo "--- actor: $AID frame at +$FX+$FY, titlebar h=$TH top=$TOP btn=$BW"

# maximize: the Cmax column is the second-from-right BW-wide slice
xdotool mousemove $((FX + 6 + 300 - BW - BW / 2)) $BY click 1
sleep 0.6
MAXGEOM=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')

# restore: the frame now sits at the workarea origin, 788 wide
xdotool mousemove $((6 + 788 - BW - BW / 2)) $((6 + BW / 2)) click 1
sleep 0.6
RESTGEOM=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
RESTPOS=$(xwininfo -id "$AID" | awk '/Absolute upper-left X:/ {x=$4} /Absolute upper-left Y:/ {y=$4} END {print x "," y}')

# --- the strip's own gestures. Double click maximizes...
xdotool mousemove $((FX + 100)) $BY click --repeat 2 --delay 80 1
sleep 0.6
DBLGEOM=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
xdotool mousemove $((6 + 788 - BW - BW / 2)) $((6 + BW / 2)) click 1  # un-maximize
sleep 0.6
# ...and button 3 opens the ops menu, which Escape dismisses.
xdotool mousemove $((FX + 100)) $BY click 3
sleep 0.6
xdotool key Escape
sleep 0.4

# --- minimize, the fourth button: third from the right
xdotool mousemove $((FX + 6 + 300 - 2 * BW - BW / 2)) $BY click 1
sleep 0.8
ICONIC=$(grep -c "WM: iconified $AID" "$HERE/wm-button.log")
# bring it back through the STATIC window list (Super+t w w, then the
# entry's own number) so the close leg below has a window to close —
# the static pick does not depend on cycle timing
xdotool key super+t; sleep 0.3
xdotool key w; sleep 0.3
xdotool key w; sleep 0.5
xdotool key 1; sleep 0.8

# --- a window that REFUSES minimize wears no minimize button, so the
#     same slice is the menu-less air next to maximize: nothing fires.
"$LINUX/whale" "$HERE/client.tcl" "стойкое" 300x200+340+300 "#ad7fa8" \
    > "$HERE/button-firm.log" &
CB=$!
sleep 1.5
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        n++; if (n == 2) { split(substr($0, RSTART + 1), a, "+")
            print "GX=" a[1] "; GY=" a[2] }
    }
}' "$HERE/wm-button.log")"
# The second frame's own line — X handed the second client the id the
# first one gave back, so the id names both and the frame names one.
FIRMBTNS=$(sed -n 's/^WM: frame .* wears \(.*\)$/\1/p' \
    "$HERE/wm-button.log" | sed -n 2p)
xdotool mousemove $((GX + 6 + 300 - 2 * BW - BW / 2)) $((GY + 6 + BW / 2)) click 1
sleep 0.6
# Counting the GESTURE and not the outcome, for the same reason: one
# real minimize press happened in this whole run, and the click on the
# slice where the button is not must add none.
FIRMICONIC=$(grep -c 'WM: titlebar minimize <1>' "$HERE/wm-button.log")

# --- the config's own button, on the left next to the menu: Lower
xdotool mousemove $((GX + 6 + BW + BW / 2)) $((GY + 6 + BW / 2)) click 1
sleep 0.6
# --- and its sharp edge: button 3 on close destroys, no polite ask
xdotool mousemove $((GX + 6 + 300 - BW / 2)) $((GY + 6 + BW / 2)) click 3
sleep 0.8

# close: rightmost button on the restored frame
xdotool mousemove $((FX + 6 + 300 - BW / 2)) $BY click 1
sleep 0.8
kill $WM $CB 2>/dev/null

echo "--- verdict"
FAIL=0
WANTMAX="788x$((600 - TOP - 6))"
if [ "$MAXGEOM" = "$WANTMAX" ]; then
    echo "OK: maximize filled the workarea ($MAXGEOM)"
else
    echo "FAIL: maximized client is $MAXGEOM, want $WANTMAX"; FAIL=1
fi
if [ "$RESTGEOM" = "300x200" ] && [ "$RESTPOS" = "$((FX + 6)),$((FY + TOP))" ]; then
    echo "OK: second toggle restored 300x200 at +$RESTPOS"
else
    echo "FAIL: restored client is $RESTGEOM at +$RESTPOS"; FAIL=1
fi
if grep -q "got WM_DELETE_WINDOW" "$HERE/button-client.log"; then
    echo "OK: close button delivered WM_DELETE_WINDOW"
else
    echo "FAIL: client never saw WM_DELETE_WINDOW"; FAIL=1
fi
if [ "$DBLGEOM" = "$WANTMAX" ]; then
    echo "OK: a double click on the strip maximized it ($DBLGEOM)"
else
    echo "FAIL: after the double click the client is $DBLGEOM, want $WANTMAX"
    FAIL=1
fi
if grep -q 'WM: titlebar title <3> .* -> winops' "$HERE/wm-button.log" \
        && grep -q 'WM: winops open' "$HERE/wm-button.log"; then
    echo "OK: button 3 on the strip opened the ops menu"
else
    echo "FAIL: button 3 on the strip did not open the menu"; FAIL=1
fi
if [ "$ICONIC" = 1 ]; then
    echo "OK: the minimize button iconified the window"
else
    echo "FAIL: $ICONIC iconify lines for the minimize button, want 1"; FAIL=1
fi
case "$FIRMBTNS" in
    *minimize*) echo "FAIL: the refusing window still wears «$FIRMBTNS»"; FAIL=1 ;;
    "") echo "FAIL: no button set logged for the refusing window"; FAIL=1 ;;
    *) echo "OK: the refusing window wears «$FIRMBTNS» — no minimize on it" ;;
esac
if [ "$FIRMICONIC" = 1 ]; then
    echo "OK: ...and the slice where the button is not fires nothing"
else
    echo "FAIL: $FIRMICONIC minimize presses in the run, want the one real"
    FAIL=1
fi
if grep -q 'WM: titlebar shade <1> .* -> Lower' "$HERE/wm-button.log"; then
    echo "OK: a button DECLARED by the config, and BOUND by it, fired Lower"
else
    echo "FAIL: the config's own titlebar button never fired"; FAIL=1
fi
if grep -q 'WM: titlebar close <3> .* -> Destroy' "$HERE/wm-button.log" \
        && ! grep -q "got WM_DELETE_WINDOW" "$HERE/button-firm.log"; then
    echo "OK: button 3 on close destroyed the client without asking it"
else
    echo "FAIL: close <3> did not destroy (or asked politely first)"; FAIL=1
fi
# Every leg above ends in a `destroy` of some Tk window of ours, which
# is the call that hangs forever on a wedged XIM server — so this test
# is the right one to insist the door is shut (see the substrate's
# `tk useinputmethods 0`).
if grep -q 'input methods off' "$HERE/wm-button.log"; then
    echo "OK: the desk holds no input contexts to be hostage to"
else
    echo "FAIL: input methods are ON — a destroy can block on the XIM"; FAIL=1
fi
if grep -q 'handler error' "$HERE/wm-button.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-button.log"
    FAIL=1
fi
exit $FAIL
