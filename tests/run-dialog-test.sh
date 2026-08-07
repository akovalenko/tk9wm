#!/bin/sh
# Regression for the live GIMP report (2026-07-27): a dialog must land
# ON the screen, centered over its parent — the plain cascade used to put
# GIMP's "Quit" dialog at +1020+860 on a 1038-tall screen, with its
# buttons below the bottom edge and unclickable.
#
# Deliberately tight screen (640x480) so a cascade would run off it.
# Also asserts ICCCM WM_STATE is set on managed clients.
. "$(dirname "$0")/common.sh"
start_xvfb 640x480x24

"$LINUX/whale" "$WMTCL" > "$HERE/wm-dialog.log" 2>&1 &
WM=$!
sleep 1.5

# main window plus, 2 s later, a transient dialog
"$LINUX/whale" "$HERE/client-dlg.tcl" 300x200 260x180 &
CP=$!
sleep 0.7
# a big client too: its cascade slot (+250+200 with a 404x428 frame) would
# hang far below a 480-tall screen — the clamp has to pull it back
"$LINUX/whale" "$HERE/client.tcl" "большой" 400x400 "#ad7fa8" &
CB=$!
sleep 4

echo "--- frames the WM placed (must all fit inside 640x480):"
grep -E 'frame \.f[0-9]+ for' "$HERE/wm-dialog.log"

echo "--- WM_STATE on the managed clients (ICCCM 4.1.3.1):"
for id in $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-dialog.log"); do
    echo "$id: $(xprop -id "$id" WM_STATE 2>&1 | tr '\n' ' ')"
done

import -display "$DISPLAY" -window root "$HERE/dialog-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/dialog-test.png"

wait $CP
wait $CB
kill $WM 2>/dev/null
echo "--- verdict"
# A leftover WM from an earlier run still owning this display would take
# the redirect, leaving OUR wm with nothing to manage — and the checks
# below would happily pass on somebody else's frames. BadAccess on
# request 2 (ChangeWindowAttributes) against the root is that situation.
if grep -q 'BadAccess request=2' "$HERE/wm-dialog.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
awk '
/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        split(substr($0, RSTART), a, "+")
        x = a[2]; y = a[3]
        if (x < 0 || y < 0 || x >= 640 || y >= 480)
            { print "FAIL: frame placed off-screen at +" x "+" y; bad = 1 }
    }
}
END { if (!bad) print "OK: every frame placed inside the screen" }
' "$HERE/wm-dialog.log"
