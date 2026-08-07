#!/bin/sh
# Regression for LAYERS: the stack is a number first and an order
# second, and one proc owns it.
#
# What is proved here is what the NUMBER buys, the fullscreen half of
# it having a suite of its own (run-fslayer-test.sh):
#
#   - a window declared `below` stays under an ordinary one however
#     lately it was raised;
#   - the EWMH pair works at run time — wmctrl -b add,above lifts a
#     window over the panel, remove puts it back, and the state is
#     published both ways;
#   - a config can put a window over the panel AND over an ACTIVE
#     fullscreen window. That is the thing no state could ever say, and
#     the owner's reason for wanting numbers (2026-08-04).
#
# Measured in PIXELS off the root, because a claim about stacking is a
# claim about what one can see. Every actor wears a colour of its own
# and sits in a rectangle of its own — two actors sharing either makes
# a pixel unable to say which of them it is looking at.
. "$(dirname "$0")/common.sh"
start_xvfb 1024x768x24

CONF="$HERE/layer-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
action терм {}
panel-button терм
# The point of numbers: over the strips and over fullscreen too.
wm-style {filter -title вожак} {layer 10}
# ...and the other end of the scale.
wm-style {filter -title подвал} {layer below}
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-layer.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-layer.log" $WM

px() { import -window root "$HERE/layer-shot.png" 2>/dev/null
       convert "$HERE/layer-shot.png" -format "%[pixel:p{$1,$2}]" info:; }
green='srgb(138,226,52)'      # вожак, layer 10
blue='srgb(52,101,164)'       # сосед, ordinary
orange='srgb(252,175,62)'     # подвал, below
purple='srgb(117,80,123)'     # the fullscreen actor
FAIL=0
ok()  { echo "OK: $1"; }
bad() { echo "FAIL: $1"; FAIL=1; }

# --- the actors, each in its own part of the screen ---------------
# вожак: bottom LEFT, hanging over the panel's band.
"$LINUX/whale" "$HERE/client.tcl" "вожак" 300x120+50+660 "#8ae234" "" "" 60 \
    > "$HERE/layer-a.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-layer.log" 'вожак'
# сосед and подвал: top RIGHT, overlapping each other and nothing else.
# сосед is born TALL, reaching down into the panel's band. Born and
# not grown: a window that grows is pulled back inside the workarea by
# the resize clamp (policy-resize), while a position the user asked for
# is honored against the SCREEN — so growing it here would measure the
# clamp instead of the layer.
"$LINUX/whale" "$HERE/client.tcl" "сосед" 300x660+600+80 "#3465a4" "" "" 60 \
    > "$HERE/layer-b.log" 2>&1 &
CB=$!
wait_client "$HERE/wm-layer.log" 'сосед'
"$LINUX/whale" "$HERE/client.tcl" "подвал" 300x200+650+150 "#fcaf3e" "" "" 60 \
    > "$HERE/layer-c.log" 2>&1 &
CC=$!
wait_client "$HERE/wm-layer.log" 'подвал'

# --- 1: layer 10 over the panel -----------------------------------
P=$(px 150 750)
case $P in
    $green) ok "a layer-10 window sits over the panel" ;;
    *)      bad "the layer-10 window is not over the panel ($P)" ;;
esac

# --- 2: below stays below, though it was raised last --------------
P=$(px 700 200)
case $P in
    $blue) ok "a below-layer window stays under an ordinary one, however lately it was raised" ;;
    *)     bad "the below-layer window came out on top ($P)" ;;
esac

# --- 3: the EWMH pair at run time ---------------------------------
# ABOVE is layer 6 and the strips are 8, so `above` means "over the
# ordinary windows" and NOT "over the panel" — which is the scale
# saying what the two words mean and is checked below both ways. Over
# the panel is what a NUMBER is for (leg 1), and that is the whole
# argument for numbering rather than a pair of flags.
#
# гость is an ordinary window mapped after сосед, so it starts on top
# of it where they overlap; one pixel there answers who is above whom.
"$LINUX/whale" "$HERE/client.tcl" "гость" 300x200+650+400 "#ef2929" "" "" 40 \
    > "$HERE/layer-d.log" 2>&1 &
CE=$!
wait_client "$HERE/wm-layer.log" 'гость'
red='srgb(239,41,41)'
OVERLAP="700 450"
NID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-layer.log" | sed -n 2p)
BEFORE=$(px $OVERLAP)
wmctrl -i -r "$NID" -b add,above
sleep 1
AFTERADD=$(px $OVERLAP)
ONPANEL=$(px 700 750)
STATE=$(xprop -id "$NID" _NET_WM_STATE | tr ',' '\n' | grep -c _NET_WM_STATE_ABOVE)
wmctrl -i -r "$NID" -b remove,above
sleep 1
AFTERDEL=$(px $OVERLAP)
echo "--- overlap pixel: $BEFORE -> add,above $AFTERADD -> remove $AFTERDEL"
case $BEFORE in
    $red) ok "the later ordinary window starts on top of the earlier one" ;;
    *)    bad "the overlap does not start with the later window ($BEFORE)" ;;
esac
case $AFTERADD in
    $blue) ok "...wmctrl -b add,above lifts the earlier one over it" ;;
    *)     bad "add,above did not lift it ($AFTERADD)" ;;
esac
case $ONPANEL in
    $blue) bad "an above-layer window climbed over the PANEL — dock is the higher layer" ;;
    *)     ok "...but not over the panel: dock (8) outranks above (6)" ;;
esac
if [ "$STATE" = 1 ]; then
    ok "...and _NET_WM_STATE_ABOVE is published back on the window"
else
    bad "_NET_WM_STATE_ABOVE is not published ($STATE)"
fi
case $AFTERDEL in
    $red) ok "...and remove puts it back among the ordinary windows" ;;
    *)    bad "remove,above left it on top ($AFTERDEL)" ;;
esac

# --- 4: over an ACTIVE fullscreen window --------------------------
"$LINUX/whale" "$HERE/client-fsdlg.tcl" полный "#75507b" \
    > "$HERE/layer-fs.log" 2>&1 &
CD=$!
sleep 3.5              # ...past its own fullscreen request at 2 s
MID=$(px 500 360)
OVER=$(px 150 750)
case $MID in
    $purple) ok "the fullscreen window owns the middle of the screen" ;;
    *)       bad "the fullscreen window is not up ($MID)" ;;
esac
case $OVER in
    $green) ok "...and the layer-10 window is STILL over it — what no state could say" ;;
    *)      bad "the layer-10 window went under fullscreen ($OVER)" ;;
esac

import -window root "$HERE/layer-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/layer-test.png"
check_invariants "$HERE/wm-layer.log" || FAIL=1
if grep -q 'handler error' "$HERE/wm-layer.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-layer.log"
    FAIL=1
fi
kill $WM $CA $CB $CC $CD $CE 2>/dev/null
exit $FAIL
