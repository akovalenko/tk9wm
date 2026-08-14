#!/bin/sh
# Regression: wm withdraw + wm deiconify must not kill the client, and the
# deiconify must get re-managed into a fresh frame.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-withdraw.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-withdraw.log" $WM
OUT=$("$LINUX/whale" "$HERE/client-w.tcl")
printf '%s\n' "$OUT"
kill $WM 2>/dev/null

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-withdraw.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
# The client reports for itself; the battery reads OK/FAIL, so the
# driver translates — this suite predated the dialect and read as
# forever-red (2026-08-11).
case $OUT in
    *"still alive, viewable=1"*)
        echo "OK: withdraw and deiconify round-tripped — the client alive\
 and viewable in a fresh frame" ;;
    *)  echo "FAIL: the client never said «still alive, viewable=1» —\
 its words above" ;;
esac
