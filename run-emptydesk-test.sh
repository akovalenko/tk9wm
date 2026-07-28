#!/bin/sh
# Regression for the empty-desk key wedge (live report, 2026-07-28):
# when the last window dies the server reverts the input focus to
# None, and with a None focus the server activates NO passive key
# grab (GrabKey demands the grab window be an ancestor of the focus
# window, or a PointerRoot focus) — so every root-grabbed chord,
# panel launchers included, went dead on an empty desk. The WM must
# park the focus whenever no window deserves it.
#
# Step 26 parked it on PointerRoot, which cured the chords and bought
# a worse bug: PointerRoot IS focus-follows-pointer. Step 32 parks it
# on a real holder window (fvwm's NoFocusWin) instead — a child of
# root, so root's passive grabs still fire, with no policy change and
# nothing to arm Tk's implicit-focus machinery. This test now demands
# the chords AND a focus that is never PointerRoot.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:99
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
Xvfb :99 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/emptydesk-config"
mkdir -p "$HERE/emptydesk-config"
cat > "$HERE/emptydesk-config/tk9wm.tcl" <<EOF
panel-button проба {match {filter -title {жилец*}} key {<Super>z} \
    launch {exec $LINUX/whale $HERE/client.tcl жилец 200x100 #8ae234 {} {} 4 &}}
wm-bind {<Super>w} {puts "MARKER: super+w fired"}
EOF

XDG_CONFIG_HOME="$HERE/emptydesk-config" \
    "$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-emptydesk.log" 2>&1 &
WM=$!
sleep 1.5

xdotool key super+w          # fresh empty desk
sleep 0.5
xdotool key super+z          # launch; the client lives 4 s
sleep 2
xdotool key super+w          # desk occupied
sleep 3                      # the client dies, the desk is empty again
xdotool key super+w          # the wedge used to start here
sleep 0.5
# The desk is genuinely empty right here — this is where the parked
# focus must be sitting on the holder and not on PointerRoot.
FOCUS=$("$LINUX/whale" "$HERE/probe-focus.tcl")
HOLDER=$(sed -n 's/^WM: focus holder up (\(0x[0-9a-f]*\)).*/\1/p' "$HERE/wm-emptydesk.log" | head -1)
xdotool key super+z          # the launcher must fire too
sleep 1.5

kill $WM 2>/dev/null

echo "--- key/focus lines:"
grep -E 'MARKER|panel проба|parking|holder|unmanaged' "$HERE/wm-emptydesk.log"
echo "--- focus on the empty desk: $FOCUS (holder $HOLDER)"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-emptydesk.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
M=$(grep -c 'MARKER: super+w fired' "$HERE/wm-emptydesk.log")
if [ "$M" = 3 ]; then
    echo "OK: the chord fired on the fresh desk, the busy desk and the re-emptied desk"
else
    echo "FAIL: $M marker lines, want 3 (the third is the empty-desk wedge)"
fi
L=$(grep -c 'panel проба: launch' "$HERE/wm-emptydesk.log")
if [ "$L" = 2 ]; then
    echo "OK: the panel launcher fired on both empty desks"
else
    echo "FAIL: $L launch lines, want 2"
fi
if grep -q 'parking focus on the holder' "$HERE/wm-emptydesk.log"; then
    echo "OK: the empty desk parked the focus on the holder"
else
    echo "FAIL: no parking line"
fi
case "$FOCUS" in
    *"focus=$HOLDER "*)
        echo "OK: the empty desk rests on the holder, not on PointerRoot" ;;
    *"focus=0x1 "*)
        echo "FAIL: the desk was left in PointerRoot — the display just\
 changed policy to focus-follows-pointer" ;;
    *)
        echo "FAIL: unexpected empty-desk focus: $FOCUS (want $HOLDER)" ;;
esac
if grep -q 'handler error' "$HERE/wm-emptydesk.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-emptydesk.log"
fi
