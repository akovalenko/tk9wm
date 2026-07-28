#!/bin/sh
# Regression for the RandR panel move: when the screen changes size
# under the WM (a resized Xephyr window announces itself as a root
# ConfigureNotify), the bottom panel strip must follow the new bottom
# edge. Xvfb cannot resize its screen (one fixed mode), so the WM runs
# in a nested resizeable Xephyr and the OUTER display resizes it.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
rm -f /tmp/.X95-lock /tmp/.X11-unix/X95 /tmp/.X96-lock /tmp/.X11-unix/X96
Xvfb :95 -screen 0 1000x800x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1
DISPLAY=:95 Xephyr :96 -screen 800x600 -resizeable >/dev/null 2>&1 &
XEPHYR=$!
sleep 1.5

rm -rf "$HERE/randr-config"
mkdir -p "$HERE/randr-config"
cat > "$HERE/randr-config/tk9wm.tcl" <<'EOF'
proc never {w} { return 0 }
panel-button тест {match never}
EOF

DISPLAY=:96 XDG_CONFIG_HOME="$HERE/randr-config" \
    "$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-randr.log" 2>&1 &
WM=$!
sleep 1.5

# a client too: the world must survive the resize, not just the panel
DISPLAY=:96 "$LINUX/whale" "$HERE/client.tcl" "жилец" 240x120 "#8ae234" "" "" 30 &
CA=$!
sleep 1

XWIN=$(DISPLAY=:95 xdotool search --class Xephyr | head -1)
DISPLAY=:95 xdotool windowsize "$XWIN" 700 500
sleep 1.5   # the debounce (200 ms) plus slack

DISPLAY=:96 import -window root "$HERE/randr-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/randr-test.png"

kill $WM $CA $XEPHYR 2>/dev/null

PH=$(sed -n 's/^WM: panel up (1 buttons, \([0-9]*\) px.*/\1/p' "$HERE/wm-randr.log" | head -1)
echo "--- panel h=$PH"
echo "--- screen/panel lines:"
grep -E 'screen ->|panel up' "$HERE/wm-randr.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-randr.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$PH" ]; then
    echo "FAIL: no panel-up line"
fi
if grep -q 'screen -> 700x500' "$HERE/wm-randr.log"; then
    echo "OK: the root resize was seen (700x500)"
else
    echo "FAIL: no «screen -> 700x500» line"
fi
if grep -q "panel up (1 buttons, $PH px, bottom/row, 800x${PH}+0+$((600 - PH)))" "$HERE/wm-randr.log"; then
    echo "OK: the panel started glued to the 600-tall bottom"
else
    echo "FAIL: no initial panel geometry line"
fi
if grep -q "panel up (1 buttons, $PH px, bottom/row, 700x${PH}+0+$((500 - PH)))" "$HERE/wm-randr.log"; then
    echo "OK: the panel followed the screen to the 500-tall bottom"
else
    echo "FAIL: the panel did not re-place after the resize"
fi
if grep -q 'handler error' "$HERE/wm-randr.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-randr.log"
fi
