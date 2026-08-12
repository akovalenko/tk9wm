#!/bin/sh
# Regression for the focus-loss discipline (the chromium wedge,
# 2026-08-12): a window the WM takes off the screen loses the focus by
# an explicit park BEFORE the unmap — a plain FocusOut the client reads
# while still mapped — never by a server revert (a FocusOut with
# detail=Ancestor under a chord's grab, no closing pair: the shape that
# left chromium's views activation stale, so the window came back to an
# honest FocusIn and stayed keyboard-dead until alt-tab bounced it by
# hand). The witness is client-focusspy.tcl, which reads its own X
# events raw through the shim.
#
# Phase B: an EWMH activation request for the window that ALREADY holds
# the focus bounces it off the holder — the fresh FocusOut/FocusIn pair
# a stale client needs (a silent no-op is what kept the wedge standing).
#
# Phase C: minimize-all (Super+d) parks ONCE and refocuses once at
# idle, instead of a park-and-aim per window — and nothing falls to
# None: the stale-fall reports the revert used to generate are gone
# with the revert itself.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 0.7; }

"$LINUX/whale" "$WMTCL" > "$HERE/wm-focusloss.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-focusloss.log" $WM

"$LINUX/whale" "$HERE/client.tcl" сосед 240x120+400+80 "#729fcf" "" "" 60 \
    > "$HERE/focusloss-neighbor.log" 2>&1 &
CL1=$!
wait_client "$HERE/wm-focusloss.log" сосед
"$LINUX/whale" "$HERE/client-focusspy.tcl" жертва \
    > "$HERE/focusloss-spy.log" 2>&1 &
CL2=$!
wait_client "$HERE/wm-focusloss.log" жертва
sleep 1
WRAP=$(sed -n 's/^SPY: watching wrapper \(0x[0-9a-f]*\)$/\1/p' \
    "$HERE/focusloss-spy.log")
echo "--- spy wrapper: $WRAP (focused as the newcomer)"

spy_lines() { wc -l < "$HERE/focusloss-spy.log"; }
wm_lines()  { wc -l < "$HERE/wm-focusloss.log"; }

# ---- phase B: activation request for the already-focused window ----
B0=$(spy_lines); BW0=$(wm_lines)
wmctrl -i -a "$WRAP"
sleep 1
B1=$(spy_lines); BW1=$(wm_lines)
SPY_B=$(sed -n "$((B0+1)),${B1}p" "$HERE/focusloss-spy.log")
WM_B=$(sed -n "$((BW0+1)),${BW1}p" "$HERE/wm-focusloss.log")
echo "--- spy saw (B, bounce):"; echo "$SPY_B" | sed 's/^/    /'

# ---- phase A: iconify the focused window (winops), bring it back ----
A0=$(spy_lines); AW0=$(wm_lines)
key alt+space                # the winops menu on the focused window...
key i                        # ...and its minimize entry
sleep 1                      # the deferred refocus runs at idle
key alt+Tab
sleep 1
A1=$(spy_lines); AW1=$(wm_lines)
SPY_A=$(sed -n "$((A0+1)),${A1}p" "$HERE/focusloss-spy.log")
WM_A=$(sed -n "$((AW0+1)),${AW1}p" "$HERE/wm-focusloss.log")
echo "--- spy saw (A, iconify round trip):"; echo "$SPY_A" | sed 's/^/    /'
echo "--- WM saw (A):"
echo "$WM_A" | grep -E 'parking|iconified|focus ->' | sed 's/^/    /'

# ---- phase C: minimize-all parks once, aims once, drops nothing ----
C0=$(wm_lines)
key super+d
sleep 1.5
C1=$(wm_lines)
WM_C=$(sed -n "$((C0+1)),${C1}p" "$HERE/wm-focusloss.log")
echo "--- WM saw (C, minimize-all):"
echo "$WM_C" | grep -E 'parking|iconified|focus ->' | sed 's/^/    /'

kill $WM $CL1 $CL2 2>/dev/null

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$HERE/wm-focusloss.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi

# B: the bounce — announced by the WM, seen by the client as a real pair
if echo "$WM_B" | grep -q 'already the focus — bouncing'; then
    echo "OK: the WM bounced an activation aimed at the focused window"
else
    echo "FAIL: no bounce line for the already-focused activation"; BAD=1
fi
BOUT=$(echo "$SPY_B" | grep -n 'focus-out' | head -1 | cut -d: -f1)
BIN=$(echo "$SPY_B" | grep -n 'focus-in' | tail -1 | cut -d: -f1)
if [ -n "$BOUT" ] && [ -n "$BIN" ] && [ "$BOUT" -lt "$BIN" ]; then
    echo "OK: the client read a fresh FocusOut/FocusIn pair off the bounce"
else
    echo "FAIL: the client saw no FocusOut/FocusIn pair (out=$BOUT in=$BIN)"; BAD=1
fi

# A: the discipline — an explicit loss BEFORE the unmap, never a revert
AOUT=$(echo "$SPY_A" | grep -n 'focus-out' | head -1 | cut -d: -f1)
AUNMAP=$(echo "$SPY_A" | grep -n '^SPY: unmap' | head -1 | cut -d: -f1)
if [ -n "$AOUT" ] && [ -n "$AUNMAP" ] && [ "$AOUT" -lt "$AUNMAP" ]; then
    echo "OK: the focus left by an explicit park before the unmap"
else
    echo "FAIL: no FocusOut before the unmap (out=$AOUT unmap=$AUNMAP)"; BAD=1
fi
# A revert walks the focus to an ANCESTOR outside any grab pair; the
# Grab/Ungrab pseudo-events a chord leaves carry detail=Ancestor too
# and are the client's to ignore by MODE — only the un-ignorable kind
# convicts.
if echo "$SPY_A" | grep 'focus-out' | grep 'detail=Ancestor' \
        | grep -q -v 'mode=Grab'; then
    echo "FAIL: a revert reached the client (FocusOut detail=Ancestor)"; BAD=1
else
    echo "OK: no revert-shaped FocusOut reached the client"
fi
ABACK=$(echo "$SPY_A" | sed -n "${AUNMAP:-1},\$p")
if echo "$ABACK" | grep -q '^SPY: map' \
        && echo "$ABACK" | grep 'focus-in' | tail -1 | grep -q 'mode=Normal'; then
    echo "OK: the round trip ends mapped with an honest FocusIn(Normal)"
else
    echo "FAIL: no map + FocusIn(Normal) after the round trip"; BAD=1
fi
if echo "$WM_A" | grep -q 'is being iconified' \
        && echo "$WM_A" | grep -q 'focus -> '; then
    echo "OK: parked on the iconify, refocused at idle"
else
    echo "FAIL: no park+deferred-refocus in the WM log for phase A"; BAD=1
fi

# C: one parking for the whole sweep, no aims at the doomed
NPARK=$(echo "$WM_C" | grep -c 'is being iconified')
NAIM=$(echo "$WM_C" | grep -c 'focus -> ')
if [ "$NPARK" = "1" ] && [ "$NAIM" = "0" ]; then
    echo "OK: minimize-all parked once and aimed at nobody doomed"
else
    echo "FAIL: minimize-all parked $NPARK times, aimed $NAIM times (want 1/0)"; BAD=1
fi

# the class the fix retires: nothing falls to None anywhere in the run
if grep -q 'focus fell to None' "$HERE/wm-focusloss.log"; then
    echo "FAIL: something still fell to None:"
    grep -B2 'focus fell to None' "$HERE/wm-focusloss.log" | sed 's/^/    /'
    BAD=1
else
    echo "OK: nothing fell to None in the whole run"
fi
if grep -q 'soft failure\|handler error' "$HERE/wm-focusloss.log"; then
    echo "FAIL: soft failures / handler errors:"
    grep 'soft failure\|handler error' "$HERE/wm-focusloss.log" | sed 's/^/    /'
    BAD=1
fi
check_invariants "$HERE/wm-focusloss.log"
[ $BAD -eq 0 ] && echo "OK: the focus leaves before the window does — parked, bounced, never reverted"
