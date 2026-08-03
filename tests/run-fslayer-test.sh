#!/bin/sh
# Regression for the fullscreen LAYER: being fullscreen is not a claim
# on the top of the stack — being ACTIVE is (owner's report,
# 2026-08-04, two symptoms of one cause).
#
#   1. Alt-Tab away from a fullscreen window and it came straight back
#      over the window just picked: the raise that picked it ended in
#      panel-on-top, which ended in "every fullscreen window to the very
#      top". There was no getting out from under it.
#   2. A fullscreen window swallowed its OWN dialog, for the same
#      reason: raise-group seats a transient above its leader, then that
#      rule put the leader back on top — and a dialog under a fullscreen
#      window is unreachable, since fullscreen took the decoration and
#      leaves no pixel showing.
#
# The rule now: a fullscreen window that lost the focus is JUST A
# WINDOW — it lies where the stacking left it, under the panel,
# undecorated, and does not come back up until you switch to it. Active,
# it goes over the strips WITH its transients above it (nothing is
# lowered to reveal a dialog — the group goes up).
#
# Measured by PIXELS off the root, because stacking is a claim about
# what one can see: each actor wears a colour nothing else has.
. "$(dirname "$0")/common.sh"
export DISPLAY=:94
rm -f /tmp/.X94-lock /tmp/.X11-unix/X94
Xvfb :94 -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

CONF="$HERE/fslayer-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
action терм {}
panel-button терм
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-fslayer.log" 2>&1 &
WM=$!
sleep 1.5

px() { import -window root "$HERE/fslayer-shot.png" 2>/dev/null
       convert "$HERE/fslayer-shot.png" -format "%[pixel:p{$1,$2}]" info:; }
# The panel is a bottom strip; a pixel well inside it.
PANELPX="300 750"
# A pixel in the middle of the desk: whoever is on top owns it.
MIDPX="500 360"

# the fullscreen actor (green) with its dialog (orange), then a plain
# neighbour (blue) to switch to
"$LINUX/whale" "$HERE/client-fsdlg.tcl" > "$HERE/fslayer-a.log" 2>&1 &
CA=$!
sleep 3            # ...past its own fullscreen request at 2 s
FSID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-fslayer.log" | sed -n 1p)

FS_PANEL=$(px $PANELPX)
echo "--- fullscreen active: panel pixel $FS_PANEL"

sleep 2            # ...past the dialog at 4 s
DLG_MID=$(px $MIDPX)
echo "--- dialog up: middle pixel $DLG_MID"

"$LINUX/whale" "$HERE/client.tcl" "сосед" 400x300+120+120 "#3465a4" "" "" 30 \
    > "$HERE/fslayer-b.log" 2>&1 &
CB=$!
sleep 2
NB_MID=$(px $MIDPX)
NB_PANEL=$(px $PANELPX)
echo "--- neighbour up: middle $NB_MID, panel $NB_PANEL"

# ...and back to the fullscreen window, the way a user would: the
# window list picks it (Alt+Tab opens it, Return takes the row).
xdotool key alt+Tab
sleep 0.7
xdotool key Return
sleep 1.2
BACK_PANEL=$(px $PANELPX)
BACK_MID=$(px $MIDPX)
echo "--- switched back: panel $BACK_PANEL, middle $BACK_MID"

kill $WM $CA $CB 2>/dev/null

echo "--- verdict"
FAIL=0
green='srgb(138,226,52)'
orange='srgb(252,175,62)'
blue='srgb(52,101,164)'

case $FS_PANEL in
    $green) echo "OK: the active fullscreen window covers the panel" ;;
    *)      echo "FAIL: active fullscreen does not own the panel pixel ($FS_PANEL)"; FAIL=1 ;;
esac
case $DLG_MID in
    $orange) echo "OK: its dialog is visible ON it — not swallowed" ;;
    *)       echo "FAIL: the dialog is not on top of its fullscreen leader ($DLG_MID)"; FAIL=1 ;;
esac
case $NB_MID in
    $blue) echo "OK: a new neighbour opens ON TOP of the fullscreen window" ;;
    *)     echo "FAIL: the neighbour did not come up over it ($NB_MID)"; FAIL=1 ;;
esac
case $NB_PANEL in
    $green) echo "FAIL: the inactive fullscreen window still covers the panel"; FAIL=1 ;;
    *)      echo "OK: ...and the panel is back on top of it ($NB_PANEL)" ;;
esac
case $BACK_PANEL in
    $green) echo "OK: switching back puts it over the panel again" ;;
    *)      echo "FAIL: back in front, it does not cover the panel ($BACK_PANEL)"; FAIL=1 ;;
esac
case $BACK_MID in
    $orange) echo "OK: ...and its dialog came up with it, still above it" ;;
    *)       echo "FAIL: the dialog did not follow the group up ($BACK_MID)"; FAIL=1 ;;
esac
if grep -q 'handler error' "$HERE/wm-fslayer.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-fslayer.log"
    FAIL=1
fi
check_invariants "$HERE/wm-fslayer.log"
exit $FAIL
