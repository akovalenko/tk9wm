#!/bin/sh
# Reproduce the live report: focus on xclock, hover an inactive xterm,
# type — does the xterm receive the input? (It must NOT.)
# Real xterm + xclock, adoption path (clients start before the WM).
. "$(dirname "$0")/common.sh"
export DISPLAY=:80
rm -f /tmp/.X80-lock /tmp/.X11-unix/X80 "$HERE/typed.txt"
Xvfb :80 -screen 0 900x700x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

xterm -geometry 60x16 -e sh -c "cat > '$HERE/typed.txt'" &
XT=$!
xclock -geometry 150x150 &
XC=$!
sleep 2                                   # both map wild, no WM yet

"$LINUX/whale" "$WMTCL" > "$HERE/wm.log" 2>&1 &
WM=$!
sleep 2.5                                 # adoption done, focus on last adopted

echo "--- wm.log after adoption:"; cat "$HERE/wm.log"
"$LINUX/whale-cli" "$TOOLS/probe-focus.tcl"

xdotool mousemove 242 226 click 1         # click into xclock body: focus clock
sleep 0.5
"$LINUX/whale-cli" "$TOOLS/probe-focus.tcl"

xdotool mousemove 130 130                 # hover the xterm body — NO click
sleep 0.5
xdotool type --delay 40 hello
xdotool key Return
sleep 1

"$LINUX/whale-cli" "$TOOLS/probe-focus.tcl"
echo "--- typed.txt (must be EMPTY if focus really was on the clock):"
cat "$HERE/typed.txt" 2>/dev/null || echo "(no file)"

echo "--- scenario A: focused clock DIES (kill) — focus must land on xterm"
kill $XC
sleep 1
"$LINUX/whale-cli" "$TOOLS/probe-focus.tcl"

echo "--- scenario B: new clock, focused, then WITHDRAWS (unmap)"
xclock -geometry 150x150 &
XC=$!
sleep 1.5
"$LINUX/whale-cli" "$TOOLS/probe-focus.tcl"
CLOCKWIN=$(xdotool search --name xclock | tail -1)
xdotool windowunmap "$CLOCKWIN"
sleep 1
"$LINUX/whale-cli" "$TOOLS/probe-focus.tcl"

echo "--- scenario C: EXTERNAL PointerRoot reset (Xephyr-style) — WM must re-assert"
"$LINUX/whale-cli" "$TOOLS/set-pointerroot.tcl"
sleep 1
"$LINUX/whale-cli" "$TOOLS/probe-focus.tcl"

echo "--- wm.log tail:"; tail -12 "$HERE/wm.log"
kill $WM $XT $XC 2>/dev/null
