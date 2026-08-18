#!/bin/sh
# Regression for the popup scroll: a list taller than the glass is
# capped to the workarea and grows two arrow bands, and every door in
# moves the right half — the keyboard moves the SELECTION and the
# glass follows it (End reaches the last row however far down it
# lives), the wheel and the arrows move the VIEW and never the
# selection, a held arrow repeats until the wall and stops there, and
# a dead-end (dimmed) arrow is a no-op that leaves the menu standing.
#
# The proofs are clicks at computed coordinates: a click lands on
# whatever row the view has under that point, so «which row fired»
# reads the scroll position back through the WM's own log. The
# geometry comes from the open line, the row height from the WM
# itself (<Super>i below) — nothing here guesses a font size.
#
# A menu that fits whole must not pass through the gate at all: the
# one-row m6 opens and fires without a «rows, shown» line.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1; }
click() { xdotool mousemove "$1" "$2" click "$3"; sleep 1; }

CONF="$HERE/popupscroll-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
proc m5-items {} {
    set rows {}
    for {set i 1} {$i <= 40} {incr i} {
        lappend rows [list label "ряд$i" do [list puts "TEST: m5 row $i"]]
    }
    return $rows
}
wm-menu m5 {key {<Super>5} body {m5-items}}
wm-menu m6 {key {<Super>6} items {{label один do {puts "TEST: m6 one"}}}}
wm-bind {<Super>i} {puts "TEST: ih [expr {[font metrics TitleFont -linespace] + 6}]"}
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-popupscroll.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-popupscroll.log" $WM

xdotool mousemove 400 300
key super+i

# ---- A: the keyboard reaches past the glass — End, then Return
key super+5
key End
key Return

# The standing menu's geometry, read once: the rows and the pointer's
# monitor never change, so every later open lands the same.
GEO=$(sed -n 's/.*WM: menu m5 open (40 items) \([0-9]*x[0-9]*+[0-9]*+[0-9]*\).*/\1/p' \
    "$HERE/wm-popupscroll.log" | head -1)
W=${GEO%%x*}; rest=${GEO#*x}
H=${rest%%+*}; xy=${rest#*+}
X=${xy%%+*}; Y=${xy#*+}
IH=$(sed -n 's/.*TEST: ih \([0-9]*\).*/\1/p' "$HERE/wm-popupscroll.log" | head -1)
VIS=$(sed -n 's/.*WM: popup \.menu: 40 rows, \([0-9]*\) shown.*/\1/p' \
    "$HERE/wm-popupscroll.log" | head -1)
if [ -z "$GEO" ] || [ -z "$IH" ] || [ -z "$VIS" ]; then
    echo "FAIL: no clipped open to measure (geo=«$GEO» ih=«$IH» vis=«$VIS»)"
    kill $WM 2>/dev/null
    exit 1
fi
BAND=$(( IH * 3 / 5 )); [ $BAND -lt 10 ] && BAND=10
MIDX=$(( X + W / 2 ))
UPY=$(( Y + 1 + BAND / 2 ))            # the top arrow band
DOWNY=$(( Y + H - 1 - BAND / 2 ))      # the bottom one
ROW1Y=$(( Y + 1 + BAND + IH / 2 ))     # the first VISIBLE row
LASTY=$(( Y + H - 1 - BAND - IH / 2 )) # the last VISIBLE row
ROWE=$(( 40 - VIS + 1 ))               # the top row once at the wall

# ---- B: a dead-end arrow is a no-op and the menu stands
key super+5
click $MIDX $UPY 1
click $MIDX $ROW1Y 1        # still row 1: nothing scrolled, nothing closed

# ---- C: the wheel drives the view, one row per notch
key super+5
xdotool mousemove $MIDX $ROW1Y
xdotool click 5; sleep 1
xdotool click 5; sleep 1
xdotool click 5; sleep 1
click $MIDX $ROW1Y 1        # three notches down: row 4 under the point

# ---- D: an arrow click walks one row
key super+5
click $MIDX $DOWNY 1
click $MIDX $ROW1Y 1        # row 2

# ---- E: held, the arrow repeats to the wall and stops there
key super+5
xdotool mousemove $MIDX $DOWNY mousedown 1
sleep 2
xdotool mouseup 1
sleep 1
click $MIDX $ROW1Y 1        # the wall's top row: 40 - VIS + 1

# ---- F: End moved the glass itself — the last row sits AT the bottom
key super+5
key End
click $MIDX $LASTY 1        # row 40 under the point, or see never scrolled

# ---- G: a menu that fits whole never passes the gate
key super+6
key 1

key super+5
key End
import -window root "$HERE/popupscroll-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/popupscroll-test.png"
key Escape
sleep 1

kill $WM 2>/dev/null

echo "--- WM saw:"
grep -E 'WM: menu|WM: popup|TEST:' "$HERE/wm-popupscroll.log"

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$HERE/wm-popupscroll.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
if grep -q 'soft failure\|handler error' "$HERE/wm-popupscroll.log"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$HERE/wm-popupscroll.log"; BAD=1
fi

GATES=$(grep -c "WM: popup \.menu: 40 rows, $VIS shown" "$HERE/wm-popupscroll.log")
ALLGATES=$(grep -c 'WM: popup \.menu:' "$HERE/wm-popupscroll.log")
if [ "$GATES" = "7" ] && [ "$ALLGATES" = "7" ]; then
    echo "OK: every tall open passed the gate ($VIS of 40 shown), the fitting one never did"
else
    echo "FAIL: gate lines: $GATES of 40/$VIS (want 7), $ALLGATES total (want 7)"; BAD=1
fi
R40=$(grep -c 'TEST: m5 row 40$' "$HERE/wm-popupscroll.log")
if [ "$R40" = "2" ]; then
    echo "OK: End reached row 40 by Return, and by a click at the glass's bottom"
else
    echo "FAIL: row 40 fired $R40 times, want 2 (Return after End; click after End)"; BAD=1
fi
R1=$(grep -c 'TEST: m5 row 1$' "$HERE/wm-popupscroll.log")
if [ "$R1" = "1" ]; then
    echo "OK: the dead arrow scrolled nothing and closed nothing"
else
    echo "FAIL: row 1 fired $R1 times, want 1 (after the dead-arrow click)"; BAD=1
fi
R4=$(grep -c 'TEST: m5 row 4$' "$HERE/wm-popupscroll.log")
if [ "$R4" = "1" ]; then
    echo "OK: three wheel notches put row 4 under the standing point"
else
    echo "FAIL: row 4 fired $R4 times, want 1 (after three wheel notches)"; BAD=1
fi
R2=$(grep -c 'TEST: m5 row 2$' "$HERE/wm-popupscroll.log")
if [ "$R2" = "1" ]; then
    echo "OK: an arrow click walked exactly one row"
else
    echo "FAIL: row 2 fired $R2 times, want 1 (after one arrow click)"; BAD=1
fi
RE=$(grep -c "TEST: m5 row $ROWE\$" "$HERE/wm-popupscroll.log")
if [ "$RE" = "1" ]; then
    echo "OK: the held arrow repeated to the wall and stopped (top row $ROWE)"
else
    echo "FAIL: row $ROWE fired $RE times, want 1 (the wall after a 2s hold)"; BAD=1
fi
if grep -q 'TEST: m6 one' "$HERE/wm-popupscroll.log"; then
    echo "OK: the fitting menu fired untouched"
else
    echo "FAIL: the fitting menu never fired"; BAD=1
fi

check_invariants "$HERE/wm-popupscroll.log"
if grep -q 'WM: INVARIANT' "$HERE/wm-popupscroll.log"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the tall list scrolls by key, wheel and arrow, and the short one never changed"
exit $BAD
