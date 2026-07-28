#!/bin/sh
# Regression for the system tray: we ARE the tray manager. Two clients
# dock an icon each (Tk's own `tk systray`, the client half of XEMBED),
# one of them lets its icon go while the other keeps its — measuring
# the claim, the dock, the reparent into our cell, the enforced size,
# the strip's geometry and the undock.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:92
rm -f /tmp/.X92-lock /tmp/.X11-unix/X92
Xvfb :92 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/tray-config"
mkdir -p "$HERE/tray-config"
cat > "$HERE/tray-config/tk9wm.tcl" <<'EOF'
set-tray on
panel-button терм { launch {} }
EOF

XDG_CONFIG_HOME="$HERE/tray-config" \
    "$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-tray.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/tray-client.tcl" "#8ae234" > "$HERE/tray-client-A.log" 2>&1 &
CA=$!
sleep 1.5
"$LINUX/whale" "$HERE/tray-client.tcl" "#729fcf" 2 > "$HERE/tray-client-B.log" 2>&1 &
CB=$!
sleep 1.5

# both icons in: measure the strip and the first icon
STRIP=$(sed -n 's/^WM: tray strip \(.*\) (2 icons)/\1/p' "$HERE/wm-tray.log" | tail -1)
ICON_A=$(sed -n 's/^WM: tray: docked \(0x[0-9a-f]*\) in slot .*/\1/p' "$HERE/wm-tray.log" | head -1)
SLOT_A=$(sed -n 's/^WM: tray: docked 0x[0-9a-f]* in slot \(0x[0-9a-f]*\).*/\1/p' "$HERE/wm-tray.log" | head -1)
# xwininfo with no id waits for a MOUSE CLICK to pick a window — with
# an empty ICON_A that is a hang, not a failed measurement
if [ -n "$ICON_A" ]; then
    GEOM_A=$(xwininfo -id "$ICON_A" 2>/dev/null | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
    PARENT_A=$(xwininfo -id "$ICON_A" -children 2>/dev/null | sed -n 's/^  Parent window id: \(0x[0-9a-f]*\).*/\1/p')
fi
import -display :92 -window root "$HERE/tray-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/tray-test.png"

sleep 2                # client B destroys its icon on its own
STRIP1=$(sed -n 's/^WM: tray strip \(.*\) (1 icons)/\1/p' "$HERE/wm-tray.log" | tail -1)
ICON_B=$(sed -n 's/^WM: tray: docked \(0x[0-9a-f]*\) in slot .*/\1/p' "$HERE/wm-tray.log" | sed -n 2p)

kill $CA $CB 2>/dev/null
sleep 1
kill $WM 2>/dev/null
sleep 0.5

echo "--- strip: 2 icons «$STRIP», 1 icon «$STRIP1»"
echo "--- icon A=$ICON_A in slot $SLOT_A, parent=$PARENT_A, ${GEOM_A}; icon B=$ICON_B"
echo "--- tray lines:"
grep -E 'WM: tray' "$HERE/wm-tray.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-tray.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q '^WM: tray up (owner' "$HERE/wm-tray.log"; then
    echo "OK: the tray selection was claimed"
else
    echo "FAIL: no tray-up line — the selection was not taken"
fi
if [ "$(grep -c '^WM: tray: docked' "$HERE/wm-tray.log")" = 2 ]; then
    echo "OK: both icons docked"
else
    echo "FAIL: want 2 docked icons, got $(grep -c '^WM: tray: docked' "$HERE/wm-tray.log")"
fi
if [ -n "$PARENT_A" ] && [ "$PARENT_A" = "$SLOT_A" ]; then
    echo "OK: icon A really lives in our cell ($PARENT_A)"
else
    echo "FAIL: icon A's parent is «$PARENT_A», want the cell «$SLOT_A»"
fi
if [ "$GEOM_A" = "24x24" ]; then
    echo "OK: the icon was held at the cell size ($GEOM_A)"
else
    echo "FAIL: icon A is $GEOM_A, want 24x24"
fi
# 2 cells: 2*3 + 2*24 + 4 = 58 wide; thickness follows the panel's strip
PH=$(sed -n 's/^WM: panel up (1 buttons, \([0-9]*\) px.*/\1/p' "$HERE/wm-tray.log" | tail -1)
if [ "$STRIP" = "58x${PH}+742+$((600 - PH))" ]; then
    echo "OK: the strip sits in the corner at the panel's thickness ($STRIP)"
else
    echo "FAIL: strip «$STRIP», want 58x${PH}+742+$((600 - PH))"
fi
if [ "$STRIP1" = "30x${PH}+770+$((600 - PH))" ]; then
    echo "OK: the strip shrank when the icon left ($STRIP1)"
else
    echo "FAIL: strip after the undock «$STRIP1», want 30x${PH}+770+$((600 - PH))"
fi
if [ -n "$ICON_B" ] && grep -q "^WM: tray: undocked $ICON_B" "$HERE/wm-tray.log"; then
    echo "OK: B's icon was undocked when its client destroyed it"
else
    echo "FAIL: no undock line for B ($ICON_B)"
fi
if grep -q 'handler error' "$HERE/wm-tray.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-tray.log"
fi
if grep -q 'soft failure' "$HERE/wm-tray.log"; then
    echo "NOTE: soft failures:"; grep 'soft failure' "$HERE/wm-tray.log"
fi
