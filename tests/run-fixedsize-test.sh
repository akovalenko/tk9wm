#!/bin/sh
# Regression for PMaxSize: the half of WM_NORMAL_HINTS the desk ignored
# until an SDL window (min == max, SDL's spelling for "not resizable")
# was stretched anyway (the owner's report, 2026-08-14).
#
#  - a declared maximum CLAMPS every WM-initiated size: maximize stops
#    at the ceiling instead of the workarea, and a border drag past it
#    lands exactly on it;
#  - a FIXED-SIZE window (min == max on both axes) keeps its size, but
#    its border is not a dead spot: grabbing it CARRIES the window —
#    the title's own move, from any edge;
#  - keyboard resize on such a window is REFUSED at every door, and
#    the winops menu does not show the row that could only say no.
#
# The probes go through send-eval: the substrate's own reading of the
# hints and the menu's own row list, asserted as data rather than
# re-derived from pixels.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/fixedsize-config"
mkdir -p "$HERE/fixedsize-config"
cat > "$HERE/fixedsize-config/tk9wm.tcl" <<'EOF'
wm-bind {<Super>s} Resize
EOF
# a resizable client with a ceiling: max 400x300 over a 240x120 start
cat > "$HERE/fixedsize-config/client-capped.tcl" <<'EOF'
package require Tk
wm title . потолок
frame .f -width 240 -height 120 -background #8ae234
pack .f -expand 1 -fill both
update idletasks
wm maxsize . 400 300
chan configure stdout -buffering line
after 60000 exit
vwait forever
EOF
# a fixed-size client: `wm resizable 0 0` is Tk's min == max
cat > "$HERE/fixedsize-config/client-fixed.tcl" <<'EOF'
package require Tk
wm title . жёсткое
frame .f -width 300 -height 200 -background #ef2929
pack .f -expand 1 -fill both
update idletasks
wm resizable . 0 0
chan configure stdout -buffering line
after 60000 exit
vwait forever
EOF

LOG="$HERE/wm-fixedsize.log"
XDG_CONFIG_HOME="$HERE/fixedsize-config" \
    "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

"$LINUX/whale" "$HERE/fixedsize-config/client-capped.tcl" &
CA=$!
wait_client "$LOG" 'потолок'
"$LINUX/whale" "$HERE/fixedsize-config/client-fixed.tcl" &
CF=$!
wait_client "$LOG" 'жёсткое'

AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 1p)
FID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 2p)
TH=$(sed -n 's/^WM: titlebar h=\([0-9]*\) .*/\1/p' "$LOG" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$LOG" | head -1)
BORDER=$((TOP - TH - 2))   ;# decotop = border + h + 2, the WM's own sum
echo "--- actors: capped=$AID fixed=$FID border=$BORDER top=$TOP"

size_of() { xwininfo -id "$1" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}'; }
absx_of() { xwininfo -id "$1" | awk '/Absolute upper-left X:/ {print $4}'; }
absy_of() { xwininfo -id "$1" | awk '/Absolute upper-left Y:/ {print $4}'; }

# --- the substrate's own reading, and the menu's own row list
ask_wm() {   # ask_wm SCRIPT — evaluate in the live WM, print the answer
    printf '%s' "$1" > "$HERE/fixedsize-config/ask.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/fixedsize-config/ask.tcl"
}
# [expr] folds the log's 0x ids to the decimal spelling the WM's own
# arrays are keyed by
P_A=$(ask_wm "list [client-fixed-size-p [expr $AID]] [lrange [client-size-hints [expr $AID]] 6 7]")
P_F=$(ask_wm "list [client-fixed-size-p [expr $FID]] [lrange [client-size-hints [expr $FID]] 6 7]")
ROWS_A=$(ask_wm "set out {}; foreach r [winops-rows [expr $AID]] {lappend out [dict get \$r label]}; set out")
ROWS_F=$(ask_wm "set out {}; foreach r [winops-rows [expr $FID]] {lappend out [dict get \$r label]}; set out")

# --- maximize stops at the ceiling, and the way back still works
wmctrl -i -r "$AID" -b add,maximized_vert,maximized_horz;    sleep 1
SZ_AMAX=$(size_of "$AID")
wmctrl -i -r "$AID" -b remove,maximized_vert,maximized_horz; sleep 1
SZ_AREM=$(size_of "$AID")
wmctrl -i -r "$FID" -b add,maximized_vert,maximized_horz;    sleep 1
SZ_FMAX=$(size_of "$FID")
wmctrl -i -r "$FID" -b remove,maximized_vert,maximized_horz; sleep 1

# --- a corner drag far past the ceiling lands exactly on it
# (raised first: the cascade lays the windows over each other, and a
# press on a covered corner would land on whoever is on top)
ask_wm "raise-group [expr $AID]" >/dev/null; sleep 0.5
CX=$(absx_of "$AID"); CY=$(absy_of "$AID")
GX=$((CX + 240 + 1)); GY=$((CY + 120 + 1))       ;# 1px into the SE grip
xdotool mousemove $GX $GY mousedown 1
xdotool mousemove $((GX + 150)) $((GY + 150))
xdotool mousemove $((GX + 300)) $((GY + 300))
xdotool mouseup 1
sleep 1
SZ_ADRAG=$(size_of "$AID")
AX_DRAG=$(absx_of "$AID")

# --- the fixed window's border carries: size stands, the window moves
ask_wm "raise-group [expr $FID]" >/dev/null; sleep 0.5
FX0=$(absx_of "$FID"); FY0=$(absy_of "$FID")
EX=$((FX0 + 300 + 1)); EY=$((FY0 + 100))          ;# 1px into the east strip
xdotool mousemove $EX $EY mousedown 1
xdotool mousemove $((EX + 30)) $EY
xdotool mousemove $((EX + 60)) $EY
xdotool mouseup 1
sleep 1
SZ_FDRAG=$(size_of "$FID")
FX1=$(absx_of "$FID")

# --- keyboard resize: entered on the capped, refused on the fixed
# (focused through the WM's own door — a click aimed by arithmetic
# lands on whichever frame the cascade left on top)
ask_wm "focus-to [expr $AID] 1" >/dev/null; sleep 0.5
xdotool key --clearmodifiers super+s; sleep 0.7
xdotool key Escape; sleep 0.5
ask_wm "focus-to [expr $FID] 1" >/dev/null; sleep 0.5
xdotool key --clearmodifiers super+s; sleep 0.7

kill $WM $CA $CF 2>/dev/null

echo "--- hints as read: capped {$P_A} fixed {$P_F}"
echo "--- menu rows: capped {$ROWS_A}"
echo "---            fixed  {$ROWS_F}"
echo "--- resize lines:"
grep -E 'keyboard resize|maximize' "$LOG"
echo "--- verdict"
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ "$P_A" = "0 {400 300}" ]; then
    echo "OK: the capped client reads max 400x300, not fixed"
else
    echo "FAIL: capped hints read as «$P_A», want «0 {400 300}»"
fi
if [ "$P_F" = "1 {300 200}" ]; then
    echo "OK: the fixed client reads max == min == 300x200, fixed"
else
    echo "FAIL: fixed hints read as «$P_F», want «1 {300 200}»"
fi
case " $ROWS_A " in
    *" Resize "*) echo "OK: the capped window's menu offers Resize" ;;
    *) echo "FAIL: no Resize row for the capped window: {$ROWS_A}" ;;
esac
case " $ROWS_F " in
    *" Resize "*) echo "FAIL: the fixed window's menu still offers Resize" ;;
    *" Move "*)   echo "OK: the fixed window's menu drops Resize, keeps Move" ;;
    *) echo "FAIL: the fixed window's row list looks wrong: {$ROWS_F}" ;;
esac
if [ "$SZ_AMAX" = "400x300" ]; then
    echo "OK: maximize stopped at the declared ceiling ($SZ_AMAX)"
else
    echo "FAIL: the capped client maximized to $SZ_AMAX, want 400x300"
fi
if [ "$SZ_AREM" = "240x120" ]; then
    echo "OK: ...and unmaximize still restores the way back"
else
    echo "FAIL: after remove the capped client is $SZ_AREM, want 240x120"
fi
if [ "$SZ_FMAX" = "300x200" ]; then
    echo "OK: maximize left the fixed window its own size ($SZ_FMAX)"
else
    echo "FAIL: the fixed client maximized to $SZ_FMAX, want 300x200"
fi
if [ "$SZ_ADRAG" = "400x300" ]; then
    echo "OK: the corner drag landed exactly on the ceiling ($SZ_ADRAG)"
else
    echo "FAIL: after the drag the capped client is $SZ_ADRAG, want 400x300"
fi
if [ "$AX_DRAG" = "$CX" ]; then
    echo "OK: ...and the SE drag left the anchored corner in place"
else
    echo "FAIL: the SE drag moved the window ($CX -> $AX_DRAG)"
fi
if [ "$SZ_FDRAG" = "300x200" ]; then
    echo "OK: the border drag left the fixed size alone ($SZ_FDRAG)"
else
    echo "FAIL: after the border drag the fixed client is $SZ_FDRAG, want 300x200"
fi
if [ "$FX1" = "$((FX0 + 60))" ]; then
    echo "OK: ...and carried the window with the hand (+$((FX1 - FX0)))"
else
    echo "FAIL: the border carry moved the fixed window by $((FX1 - FX0)), want +60"
fi
if grep -q "keyboard resize $AID" "$LOG"; then
    echo "OK: keyboard resize still enters on the capped window"
else
    echo "FAIL: keyboard resize never entered on the capped window"
fi
if grep -q "keyboard resize refused — $FID is fixed-size" "$LOG"; then
    echo "OK: keyboard resize is refused on the fixed window, and says so"
else
    echo "FAIL: no refusal line for the fixed window"
fi
if grep -q "keyboard resize $FID" "$LOG"; then
    echo "FAIL: keyboard resize ENTERED on the fixed window"
else
    echo "OK: ...and the mode never entered there"
fi
if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"
fi
check_invariants "$LOG"
