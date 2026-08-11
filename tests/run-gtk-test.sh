#!/bin/sh
# GTK canary: zenity (GTK3) must start, get framed and survive under the
# WM; optionally poke gimp if it can run in this environment at all.
. "$(dirname "$0")/common.sh"
start_xvfb 900x700x24

"$LINUX/whale" "$WMTCL" &
WM=$!
sleep 1.5

zenity --info --text "tk9wm GTK canary" --title zenity-canary &
ZP=$!
sleep 4
if kill -0 $ZP 2>/dev/null; then
    ZALIVE=1; echo "DRIVER: zenity alive under the WM"
else
    ZALIVE=0; wait $ZP; echo "DRIVER: zenity EXITED early, code $?"
fi
import -display "$DISPLAY" -window root "$HERE/gtk-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/gtk-test.png"

GIMP=untried
if command -v gimp >/dev/null; then
    timeout 20 gimp >/dev/null 2>"$HERE/gimp.err" &
    GP=$!
    sleep 15
    if kill -0 $GP 2>/dev/null; then
        GIMP=alive; echo "DRIVER: gimp alive under the WM"
    else
        wait $GP; GST=$?
        echo "DRIVER: gimp exited, code $GST (139=segv); stderr:"
        head -5 "$HERE/gimp.err"
        # snap confinement cannot even start gimp in a sandboxed
        # environment — that is the rig's hole, not the WM's: the leg
        # is declared untried rather than failed (2026-08-11)
        if grep -qiE 'snap|read-only file system' "$HERE/gimp.err"; then
            GIMP=untriable
        else
            GIMP=died
        fi
    fi
    kill $GP 2>/dev/null
fi

kill $ZP $WM 2>/dev/null

echo "--- verdict"
# the battery reads OK/FAIL — this suite predated the dialect and
# read as forever-red (2026-08-11)
if [ "$ZALIVE" = 1 ]; then
    echo "OK: zenity (GTK3) framed and alive under the WM"
else
    echo "FAIL: zenity exited early under the WM"
fi
case $GIMP in
    alive)     echo "OK: gimp framed and alive under the WM" ;;
    untried)   echo "OK: no gimp on this machine — the canary was zenity alone" ;;
    untriable) echo "OK: gimp cannot start on this rig (snap confinement) —\
 the canary was zenity alone" ;;
    died)      echo "FAIL: gimp died under the WM — its stderr above" ;;
esac
