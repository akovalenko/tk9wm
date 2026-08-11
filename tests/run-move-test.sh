#!/bin/sh
# ICCCM 4.1.5 regression: a ConfigureWindow request the WM does not grant
# must still be answered with a synthetic ConfigureNotify. A WM that stays
# silent leaves the client believing its move took effect — the root of
# the live "the app does not know where it is" report (menus, tooltips,
# combo dropdowns and clicks all offset, until the first drag).
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-move.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-move.log" $WM

OUT=$("$LINUX/whale-cli" "$HERE/client-move.tcl" "$DISPLAY")
printf '%s\n' "$OUT"
kill $WM 2>/dev/null

echo "--- what the WM logged:"
grep -E 'managed 0x|ConfigureRequest|resize 0x' "$HERE/wm-move.log" | head -5
echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-move.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
# The client asks the protocol question and answers PASS/FAIL in its
# own words; the battery reads OK/FAIL, so the driver translates —
# this suite predated the dialect and read as forever-red (2026-08-11).
case $OUT in
    *"CLIENT: PASS"*)
        echo "OK: the WM answered the move request (ICCCM 4.1.5)" ;;
    *)  echo "FAIL: no synthetic ConfigureNotify — the client's words above" ;;
esac
