#!/bin/sh
# Regression for the clock's CALENDAR — the click the widget's header
# promised (the owner's ask, 2026-08-11): three months on one sheet,
# the current one flanked by both neighbours, in the workarea corner
# nearest the clock. Measured here:
#
#  - a click on the clock opens it, the same click again closes it —
#    a toggle, and both say so in the log;
#  - the sheet lands FLUSH in the corner the panel's SIDE names —
#    bottom right for a bottom panel, top right for a top one (an air
#    gap read as a resize border, and the sheet does not resize);
#  - a click on the sheet itself dismisses it: a glance, not a
#    conversation.
. "$(dirname "$0")/common.sh"
start_xvfb 900x500x24
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
action терминал { launch {exec xterm &} }
panel-button терминал
wm-widget clock -type clock -on {panel default}
EOF
sleep 1

LOG="$HERE/wm-calendar.log"
XDG_CONFIG_HOME="$CONF" "$WHALE" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM
sleep 2

area()    { sed -n 's/^WM: widget area \([0-9x+]*\) .*/\1/p' "$LOG" | tail -1; }
calgeom() { sed -n 's/^WM: calendar open \([0-9x+]*\) .*/\1/p' "$LOG" | tail -1; }
bandgeom() { sed -n 's/^WM: panel default up (.*, \([0-9x+]*\))$/\1/p' "$LOG" \
    | tail -1; }
opens()   { grep -c '^WM: calendar open '  "$LOG"; }
closes()  { grep -c '^WM: calendar closed' "$LOG"; }
click() {   # click WxH+X+Y — one press on the middle of that rectangle
    set -- $(echo "$1" | sed 's/[x+]/ /g')
    xdotool mousemove $(($3 + $1 / 2)) $(($4 + $2 / 2)) click 1
    sleep 1
}

# --- open by the clock, close by the clock: the toggle
click "$(area)"
CAL=$(calgeom)
click "$(area)"
TOGGLED="$(opens) $(closes)"

# --- open again, dismiss by a click on the sheet itself
click "$(area)"
import -display "$DISPLAY" -window root "$HERE/calendar-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/calendar-test.png"
click "$(calgeom)"
DISMISSED="$(opens) $(closes)"
BOTTOMBAND=$(bandgeom)

# --- the same clock on a TOP panel: the corner follows the side
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
set-panel-side top
action терминал { launch {exec xterm &} }
panel-button терминал
wm-widget clock -type clock -on {panel default}
EOF
"$WHALE_CLI" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
sleep 1.5
click "$(area)"
TOPCAL=$(calgeom)
TOPBAND=$(bandgeom)

kill $WM 2>/dev/null

echo "--- calendar lines:"
grep -E '^WM: calendar ' "$LOG"
echo "--- bottom panel band $BOTTOMBAND, sheet $CAL"
echo "--- top panel band $TOPBAND, sheet $TOPCAL"

echo "--- verdict"
FAIL=0
if [ "$TOGGLED" = "1 1" ]; then
    echo "OK: the clock's click is a toggle — one open, one close"
else
    echo "FAIL: open/close counts after two clicks: $TOGGLED"; FAIL=1
fi
if [ "$DISMISSED" = "2 2" ]; then
    echo "OK: a click on the sheet dismisses it"
else
    echo "FAIL: open/close counts after the sheet was clicked: $DISMISSED"
    FAIL=1
fi
# The corner arithmetic, against the workarea the band leaves: flush
# on the workarea's edges both ways.
geom() { echo "$1" | sed 's/[x+]/ /g'; }
set -- $(geom "$CAL");     CW=$1 CH=$2 CX=$3 CY=$4
set -- $(geom "$BOTTOMBAND"); BY=$4
if [ -n "$CW" ] && [ $((CX + CW)) -eq 900 ] \
        && [ $((CY + CH)) -eq "${BY:-0}" ]; then
    echo "OK: bottom panel -> the sheet sits flush in the bottom right of\
 the workarea ($CAL against a band at y=$BY)"
else
    echo "FAIL: bottom panel put the sheet at «$CAL» (band $BOTTOMBAND)"
    FAIL=1
fi
set -- $(geom "$TOPCAL");  TW=$1 TH=$2 TX=$3 TY=$4
set -- $(geom "$TOPBAND"); TBH=$2
if [ -n "$TW" ] && [ $((TX + TW)) -eq 900 ] && [ "$TY" = "${TBH:-0}" ]; then
    echo "OK: top panel -> the sheet moved flush to the top right, under\
 the strip ($TOPCAL under a ${TBH}px band)"
else
    echo "FAIL: top panel put the sheet at «$TOPCAL» (band $TOPBAND)"; FAIL=1
fi
exit $FAIL
