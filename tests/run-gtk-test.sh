#!/bin/sh
# GTK canary: zenity (GTK3) must start, get framed and survive under the
# WM; optionally poke gimp if it can run in this environment at all.
. "$(dirname "$0")/common.sh"
export DISPLAY=:82
rm -f /tmp/.X82-lock /tmp/.X11-unix/X82
Xvfb :82 -screen 0 900x700x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" &
WM=$!
sleep 1.5

zenity --info --text "tk9wm GTK canary" --title zenity-canary &
ZP=$!
sleep 4
if kill -0 $ZP 2>/dev/null; then
    echo "DRIVER: zenity alive under the WM"
else
    wait $ZP; echo "DRIVER: zenity EXITED early, code $?"
fi
import -display :82 -window root "$HERE/gtk-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/gtk-test.png"

if command -v gimp >/dev/null; then
    timeout 20 gimp >/dev/null 2>"$HERE/gimp.err" &
    GP=$!
    sleep 15
    if kill -0 $GP 2>/dev/null; then
        echo "DRIVER: gimp alive under the WM"
    else
        wait $GP; echo "DRIVER: gimp exited, code $? (139=segv); stderr:"
        head -5 "$HERE/gimp.err"
    fi
    kill $GP 2>/dev/null
fi

kill $ZP $WM 2>/dev/null
