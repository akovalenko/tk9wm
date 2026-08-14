#!/bin/sh
# Reproduce the live report: focus on xclock, hover an inactive xterm,
# type — does the xterm receive the input? (It must NOT.)
# Real xterm + xclock, adoption path (clients start before the WM).
. "$(dirname "$0")/common.sh"
rm -f "$HERE/typed.txt"
start_xvfb 900x700x24

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
TYPED=$(cat "$HERE/typed.txt" 2>/dev/null)
echo "--- typed.txt (must be EMPTY if focus really was on the clock):"
echo "${TYPED:-(empty)}"

# a probe answer is «focus=0xN revert=R»; a REAL window is anything
# past the protocol constants — None (0x0) and PointerRoot (0x1)
real_focus() {
    _pf=$("$LINUX/whale-cli" "$TOOLS/probe-focus.tcl")
    printf '%s\n' "$_pf"
    _f=$(printf '%s\n' "$_pf" | sed -n 's/.*focus=\(0x[0-9a-f]*\).*/\1/p' | head -1)
    [ -n "$_f" ] && [ "$(( _f + 0 ))" -gt 1 ]
}

echo "--- scenario A: focused clock DIES (kill) — focus must land on xterm"
kill $XC
sleep 1
real_focus; A=$?

echo "--- scenario B: new clock, focused, then WITHDRAWS (unmap)"
xclock -geometry 150x150 &
XC=$!
sleep 1.5
"$LINUX/whale-cli" "$TOOLS/probe-focus.tcl"
CLOCKWIN=$(xdotool search --name xclock | tail -1)
xdotool windowunmap "$CLOCKWIN"
sleep 1
real_focus; B=$?

echo "--- scenario C: EXTERNAL PointerRoot reset (Xephyr-style) — WM must re-assert"
"$LINUX/whale-cli" "$TOOLS/set-pointerroot.tcl"
sleep 1
real_focus; C=$?

echo "--- wm.log tail:"; tail -12 "$HERE/wm.log"
kill $WM $XT $XC 2>/dev/null

echo "--- verdict"
# the battery reads OK/FAIL — this suite predated the dialect and read
# as forever-red (2026-08-11). The measurements above stay for the eye;
# what is asserted is the report the suite was born from (typing must
# not leak into the hovered xterm) and that every scenario leaves the
# focus parked on a real window, never None or PointerRoot.
if grep -q 'BadAccess request=2' "$HERE/wm.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$TYPED" ]; then
    echo "OK: the hovered xterm stayed deaf — the focus was really on the clock"
else
    echo "FAIL: the hovered xterm received «$TYPED» without a click"
fi
if [ "$A" = 0 ]; then
    echo "OK: a dying focus holder leaves the focus on a real window"
else
    echo "FAIL: after the clock died the focus fell to None/PointerRoot"
fi
if [ "$B" = 0 ]; then
    echo "OK: a withdrawing focus holder leaves the focus on a real window"
else
    echo "FAIL: after the withdraw the focus fell to None/PointerRoot"
fi
if [ "$C" = 0 ]; then
    echo "OK: an external PointerRoot reset is re-asserted by the desk"
else
    echo "FAIL: the desk left the focus on PointerRoot after the reset"
fi
