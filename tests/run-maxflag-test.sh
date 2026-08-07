#!/bin/sh
# Regression for `set-maximize keep|drop` — what a HAND resize does to
# the maximized mark. The scenario is the owner's report (2026-07-29,
# where the two resizes seemed to disagree; they never did): maximize,
# shrink by mouse and by keyboard, hit the toggle and see which way it
# goes. Back to 300x200 means the mark survived and the toggle
# RESTORED; back to the workarea means it was shed and the toggle
# MAXIMIZED.
#
# Both readings are measured, and both resizes under each, because the
# whole point of putting the rule in resize-by-edge is that the pointer
# and the keyboard cannot drift apart on it. The reload in the middle
# is how the second config gets in without disturbing the client.
. "$(dirname "$0")/common.sh"
start_xvfb

CONF="$HERE/maxflag-config"
rm -rf "$CONF"; mkdir -p "$CONF"
echo 'set-maximize keep' > "$CONF/tk9wm.tcl"

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$HERE/wm-maxflag.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-maxflag.log" $WM
"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" "" "" 120 &
CA=$!
wait_client "$HERE/wm-maxflag.log" 'жертва'

VID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-maxflag.log" | head -1)
key() { xdotool key "$@"; sleep 0.4; }
drag() { xdotool mousemove "$1" "$2" mousedown 1 mousemove "$3" "$4" mouseup 1; sleep 0.5; }
size() { xwininfo -id "$VID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}'; }

# Pull the client's bottom-right corner in by 100x80. The grip is a few
# pixels OUTSIDE the client, on the frame's border.
mouse_shrink() {
    eval "$(xwininfo -id "$VID" | awk '
        /Absolute upper-left X/ {print "FX=" $NF}
        /Absolute upper-left Y/ {print "FY=" $NF}
        /Width:/ {print "W=" $2} /Height:/ {print "H=" $2}')"
    drag $((FX + W + 3)) $((FY + H + 3)) $((FX + W - 97)) $((FY + H - 77))
}
# The same shrink from the keyboard: the se handle, 10 px a step.
kbd_shrink() {
    key alt+space; key s
    i=0; while [ $i -lt 10 ]; do xdotool key Left; i=$((i + 1)); done
    i=0; while [ $i -lt 8 ];  do xdotool key Up;   i=$((i + 1)); done
    sleep 0.4
    key Return
}
maximize() { key alt+space; key x; }

maximize;     MAXED=$(size)
mouse_shrink; KEEP_MOUSE_CUT=$(size)
maximize;     KEEP_MOUSE=$(size)      # keep: restores 300x200
maximize                              # ...maximized again
kbd_shrink
maximize;     KEEP_KBD=$(size)        # keep: restores 300x200 again
maximize                              # leave it maximized for pass 2

echo 'set-maximize drop' > "$CONF/tk9wm.tcl"
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
sleep 1

mouse_shrink; DROP_MOUSE_CUT=$(size)
maximize;     DROP_MOUSE=$(size)      # drop: maximizes, back to the workarea
kbd_shrink
maximize;     DROP_KBD=$(size)        # drop: maximizes again

kill $WM $CA 2>/dev/null

echo "--- maximized to $MAXED; the hand cuts landed at\
 $KEEP_MOUSE_CUT / $DROP_MOUSE_CUT"
echo "--- log:"
grep -E 'no longer maximized|set-maximize|config ' "$HERE/wm-maxflag.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-maxflag.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
expect() {   # what wanted got
    if [ "$2" = "$3" ]; then
        echo "OK: $1 ($3)"
    else
        echo "FAIL: $1 — wanted $2, got $3"
    fi
}
expect "the mark survives a mouse resize under keep, so the toggle restores" \
    "300x200" "$KEEP_MOUSE"
expect "...and survives the keyboard just the same" "300x200" "$KEEP_KBD"
expect "the mark is shed by a mouse resize under drop, so the toggle maximizes" \
    "$MAXED" "$DROP_MOUSE"
expect "...and is shed by the keyboard just the same" "$MAXED" "$DROP_KBD"
expect "drop said so, twice, and keep never did" \
    "2" "$(grep -c 'no longer maximized' "$HERE/wm-maxflag.log")"
