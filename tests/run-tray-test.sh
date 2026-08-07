#!/bin/sh
# Regression for the system tray: we ARE the tray manager. Two clients
# dock an icon each (Tk's own `tk systray`, the client half of XEMBED),
# one of them lets its icon go while the other keeps its — measuring
# the claim, the dock, the reparent into our cell, the enforced size,
# the strip's geometry and the undock.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/tray-config"
mkdir -p "$HERE/tray-config"
cat > "$HERE/tray-config/tk9wm.tcl" <<'EOF'
set-tray on
action терм {}
panel-button терм
EOF

XDG_CONFIG_HOME="$HERE/tray-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-tray.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-tray.log" $WM

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
import -display "$DISPLAY" -window root "$HERE/tray-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/tray-test.png"
# WHAT IS ACTUALLY ON THE GLASS, measured HERE where both icons are up.
# Everything else in this file is about ids, parents and geometry — and
# all of it passed on a desk whose tray showed nothing at all: the
# panel's window spans the whole band including the tray's corner, so a
# stacking mistake paints the strip over with the panel's own
# background and leaves every structural fact true (the owner's desk,
# 2026-08-04, cured by the layer ranks). A pixel of the icon's own
# colour is the one thing that cannot be true while the tray is blank.
PH=$(sed -n 's/^WM: panel [^ ]* up (1 buttons, \([0-9]*\) px.*/\1/p' "$HERE/wm-tray.log" | tail -1)
SX=$(echo "$STRIP" | sed 's/.*+\([0-9]*\)+[0-9]*$/\1/')
SY=$(echo "$STRIP" | sed 's/.*+\([0-9]*\)$/\1/')
# the middle of the FIRST cell: 3px of pad, then a 24px square
TRAYPX=$(convert "$HERE/tray-test.png" \
    -format "%[pixel:p{$((SX + 15)),$((SY + PH / 2))}]" info: 2>/dev/null)
echo "--- tray pixel at $((SX + 15)),$((SY + PH / 2)): $TRAYPX"

sleep 2                # client B destroys its icon on its own
STRIP1=$(sed -n 's/^WM: tray strip \(.*\) (1 icons)/\1/p' "$HERE/wm-tray.log" | tail -1)
ICON_B=$(sed -n 's/^WM: tray: docked \(0x[0-9a-f]*\) in slot .*/\1/p' "$HERE/wm-tray.log" | sed -n 2p)

# A DECOY: a window that carries _XEMBED_INFO but was never docked —
# fcitx5's input and menu windows are exactly this, and an adoption
# that goes by the property instead of by its own record swallows them
# whole (owner's live desk, 2026-07-29: a 425x196 menu window folded
# into a 36x36 cell). It must still be a child of the root, untouched,
# after the restart below.
"$LINUX/whale" "$HERE/plug-decoy.tcl" > "$HERE/tray-decoy.log" 2>&1 &
CD=$!
sleep 1.5
DECOY=$(sed -n 's/^DECOY: window \(0x[0-9a-f]*\)/\1/p' "$HERE/tray-decoy.log")

# Restart in place: A's icon goes back to the root and must be picked
# up again by the fresh instance WITHOUT its client doing anything —
# the client is not obliged to hear the MANAGER announcement, and
# Chrome does not (live measurement, 2026-07-29).
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
sleep 3
PARENT_A2=$(xwininfo -id "$ICON_A" -children 2>/dev/null | sed -n 's/^  Parent window id: \(0x[0-9a-f]*\).*/\1/p')
SLOT_A2=$(sed -n 's/^WM: tray: docked 0x[0-9a-f]* in slot \(0x[0-9a-f]*\).*/\1/p' "$HERE/wm-tray.log" | tail -1)

DECOY_PARENT=""
if [ -n "$DECOY" ]; then
    DECOY_PARENT=$(xwininfo -id "$DECOY" -children 2>/dev/null | sed -n 's/^  Parent window id: \(0x[0-9a-f]*\).*/\1/p')
fi
ROOTID=$(xwininfo -root 2>/dev/null | sed -n 's/^xwininfo: Window id: \(0x[0-9a-f]*\).*/\1/p')

# A COLOUR ERASED MUST LEAVE THE STRIP TOO: the icon cells are
# re-made on the next layout, the strip and its backdrop are not — so
# a reset that only put the variable back left the space around the
# icons wearing the old customization.
qt() { printf '%s\n' "$1" > "$HERE/tray-config/q.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/tray-config/q.tcl"; }
qt 'custom-write {set-tray-background #ff00ff}' >/dev/null
sleep 0.5
TRAYCOLOR1=$(qt 'list [.tray cget -background] $::tray_bg')
qt 'custom-erase set-tray-background' >/dev/null
sleep 1.5
TRAYCOLOR2=$(qt 'list [.tray cget -background] $::tray_bg')

kill $CA $CB $CD 2>/dev/null
sleep 1
kill $WM 2>/dev/null
sleep 0.5

# ---- A TRAY-ONLY DESK STILL HAS A BAND ----
# `set-tray on` and nothing else left the desk with no strip at all: a
# panel was built for its BUTTONS, and the band a tray sits in is a
# panel. The owner turned the tray on and nothing appeared until he
# added a clock (2026-08-02).
rm -rf "$HERE/traybare-config"
mkdir -p "$HERE/traybare-config"
printf '%s\n' 'set-welcome off' 'set-tray on' \
    > "$HERE/traybare-config/tk9wm.tcl"
XDG_CONFIG_HOME="$HERE/traybare-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-traybare.log" 2>&1 &
WMBARE=$!
sleep 2
BARE=$(printf '%s\n' 'set out {}
    foreach n [panel-names] {
        if {[info exists ::panel_win($n)]} {
            lappend out $n [winfo exists $::panel_win($n)] \
                [winfo ismapped $::panel_win($n)]
        }
    }
    list strips $out tray [expr {[winfo exists .tray] ? 1 : 0}]' \
    > "$HERE/traybare-config/q.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/traybare-config/q.tcl")
kill $WMBARE 2>/dev/null
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
# only the first lifetime: the restart below docks A a second time
DOCKED=$(awk '/restart requested/ {exit} /^WM: tray: docked/ {n++} END {print n+0}' \
    "$HERE/wm-tray.log")
if [ "$DOCKED" = 2 ]; then
    echo "OK: both icons docked"
else
    echo "FAIL: want 2 docked icons before the restart, got $DOCKED"
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
# 2 cells: 2*3 + 2*24 + 4 = 58 wide; thickness follows the panel's
# strip A PIXEL SHORT — the band's inner row is the panel's hairline
# and the tray backs off it (PH is read up where the pixel is taken,
# which needs it too)
if [ "$STRIP" = "58x$((PH - 1))+742+$((600 - PH + 1))" ]; then
    echo "OK: the strip sits in the corner, a pixel short of the hairline ($STRIP)"
else
    echo "FAIL: strip «$STRIP», want 58x$((PH - 1))+742+$((600 - PH + 1))"
fi
if [ "$STRIP1" = "30x$((PH - 1))+770+$((600 - PH + 1))" ]; then
    echo "OK: the strip shrank when the icon left ($STRIP1)"
else
    echo "FAIL: strip after the undock «$STRIP1», want 30x$((PH - 1))+770+$((600 - PH + 1))"
fi
if [ -n "$ICON_B" ] && grep -q "^WM: tray: undocked $ICON_B" "$HERE/wm-tray.log"; then
    echo "OK: B's icon was undocked when its client destroyed it"
else
    echo "FAIL: no undock line for B ($ICON_B)"
fi
if grep -q "^WM: tray: $ICON_A was ours and is orphaned" "$HERE/wm-tray.log"; then
    echo "OK: the restarted WM found A's orphaned icon by itself"
else
    echo "FAIL: A's icon was not picked up as an orphan after the restart"
fi
if [ -n "$PARENT_A2" ] && [ "$PARENT_A2" = "$SLOT_A2" ]; then
    echo "OK: A's icon sits in a cell of the NEW instance ($PARENT_A2)"
else
    echo "FAIL: after the restart A's parent is «$PARENT_A2», cell «$SLOT_A2»"
fi
if [ -n "$DECOY" ] && [ "$DECOY_PARENT" = "$ROOTID" ]; then
    echo "OK: the decoy plug was left alone (still a child of the root)"
else
    echo "FAIL: the decoy $DECOY was adopted — parent «$DECOY_PARENT», root «$ROOTID»"
fi
case "$TRAYPX" in
    srgb\(138,226,52\)) echo "OK: the icon is ON THE GLASS, not just in the tree ($TRAYPX)" ;;
    *) echo "FAIL: the tray cell shows «$TRAYPX», not the icon's own green —\
 docked and invisible"; FAIL=1 ;;
esac
if grep -q 'handler error' "$HERE/wm-tray.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-tray.log"
fi
if grep -q 'soft failure' "$HERE/wm-tray.log"; then
    echo "NOTE: soft failures:"; grep 'soft failure' "$HERE/wm-tray.log"
fi

echo "--- a tray with no buttons: $BARE"
case "$BARE" in
    "strips {default 1 1} tray 1")
        echo "OK: a tray with no buttons still gets a band to sit in" ;;
    *) echo "FAIL: the tray-only desk: $BARE" ;;
esac
echo "--- tray colour: after custom {$TRAYCOLOR1}, after erase {$TRAYCOLOR2}"
case "$TRAYCOLOR1|$TRAYCOLOR2" in
    "{#ff00ff} #ff00ff|{#2e3436} #2e3436")
        echo "OK: the strip wears the customization and gives it back on erase" ;;
    *) echo "FAIL: tray colour: {$TRAYCOLOR1} then {$TRAYCOLOR2}" ;;
esac
