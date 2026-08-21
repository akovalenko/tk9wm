#!/bin/sh
# Regression for the place rule as a maximized STATE, per axis, and for
# As-Usual — the winops row that re-places a window as its rule says.
#
# An axis a `place` holds at the whole workarea (max, an explicit 100%,
# or the fill of an unclaimed axis) is maximized on that axis: a window
# born by `50%right` publishes MAXIMIZED_VERT alone, its client remove
# releases the axis (unforced rule), and a FORCED `50%right` bounces
# that same remove — the pin, per axis now. As-Usual puts the window
# back where the rule says after it has been dragged about or resized,
# re-marking the held axis; the way back it records is the geometry the
# pick displaced, so the Maximize-V toggle right after restores exactly
# that. The row itself is gated: a window whose style has no place rule
# does not carry it.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 0.6; }
LOG="$HERE/wm-asusual.log"
CONF="$HERE/asusual-config"
askw() {
    printf '%s\n' "$1" > "$CONF/q.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1
}
labels_of() {
    askw 'join [lmap i [.winops.t item children root] {
    .winops.t item element cget $i C0 eTxt -text
}] ,'
}

rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
action dummy {launch {exec true &}}
panel-button dummy
wm-style {filter -title правое}   {place 50%right}
wm-style {filter -title прибитое} {place {50%right force}}
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

PH=$(sed -n 's/^WM: panel [^ ]* up (1 buttons, \([0-9]*\) px.*/\1/p' "$LOG" | head -1)
eval "$(sed -n 's/^WM: titlebar h=\([0-9]*\) top=\([0-9]*\).*/TITLEH=\1; TOP=\2/p' \
        "$LOG" | head -1)"
B=$((TOP - TITLEH - 2))
WAH=$((600 - ${PH:-38}))
CW=$((400 - 2 * B))          # the client in the right HALF...
MAXH=$((WAH - TOP - B))      # ...at the workarea's full height
HALF="${CW}x${MAXH}"

size_of() { xwininfo -id "$1" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}'; }
frame_of() {   # the FRAME's rect, computed off the client xwininfo sees
    xwininfo -id "$1" | awk -v b="$B" -v t="$TOP" '
        /Absolute upper-left X/ {x=$NF-b} /Absolute upper-left Y/ {y=$NF-t}
        /Width:/ {w=$2+2*b} /Height:/ {h=$2+t+b} END {print w "x" h "+" x "+" y}'
}
state_of() { xprop -id "$1" _NET_WM_STATE | sed 's/.*= //'; }
click_title() {
    eval "$(xwininfo -id "$1" | awk '
        /Absolute upper-left X/ {print "CX=" $NF}
        /Absolute upper-left Y/ {print "CY=" $NF}')"
    xdotool mousemove $((CX + 40)) $((CY - TOP + B + TITLEH / 2)) click 1
    sleep 0.5
}

"$LINUX/whale" "$HERE/client.tcl" "жертва" 240x120 "#8ae234" "" "" 90 &
CA=$!
wait_client "$LOG" 'жертва'
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | head -1)

# ---- the plain window: no place rule, no As-Usual row ----
key alt+space
LABELS_A=$(labels_of)
key Escape

# ---- born by the rule: right half, full height, VERT published ----
# "-" asks for NOTHING, so the rule has no -geometry claim to yield to.
"$LINUX/whale" "$HERE/client.tcl" "правое" - "#fce94f" "" "" 90 &
CR=$!
wait_client "$LOG" 'правое'
RID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 2p)
G_BORN=$(frame_of "$RID")
ST_BORN=$(state_of "$RID")

# ---- the unforced rule: a client's remove releases the held axis ----
wmctrl -i -r "$RID" -b remove,maximized_vert; sleep 1
SZ_REL=$(size_of "$RID")
ST_REL=$(state_of "$RID")

# ---- As-Usual from the menu: back by the rule, VERT again ----
click_title "$RID"
key alt+space
LABELS_R=$(labels_of)
key u
G_BACK=$(frame_of "$RID")
ST_BACK=$(state_of "$RID")

# ---- dragged away by the title, As-Usual brings it home ----
eval "$(xwininfo -id "$RID" | awk '
    /Absolute upper-left X/ {print "CX=" $NF}
    /Absolute upper-left Y/ {print "CY=" $NF}')"
xdotool mousemove $((CX + 40)) $((CY - TOP + B + TITLEH / 2)) \
    mousedown 1 mousemove $((CX - 200)) $((CY + 100)) mouseup 1
sleep 0.6
G_MOVED=$(frame_of "$RID")
key alt+space; key u
G_HOME=$(frame_of "$RID")

# ---- a hand resize sheds the mark; As-Usual re-marks; the toggle
# right after restores the very geometry the pick displaced ----
eval "$(xwininfo -id "$RID" | awk '
    /Absolute upper-left X/ {print "FX=" $NF}
    /Absolute upper-left Y/ {print "FY=" $NF}
    /Width:/ {print "W=" $2} /Height:/ {print "H=" $2}')"
xdotool mousemove $((FX + W + 3)) $((FY + H + 3)) mousedown 1 \
    mousemove $((FX + W - 97)) $((FY + H - 77)) mouseup 1
sleep 0.6
G_CUT=$(frame_of "$RID")
ST_CUT=$(state_of "$RID")
key alt+space; key u
G_AGAIN=$(frame_of "$RID")
key alt+space; key v          # Maximize-V toggles the held axis OFF...
G_UNDO=$(frame_of "$RID")     # ...back to what the pick displaced

# ---- the forced rule pins its axis against a client's remove ----
"$LINUX/whale" "$HERE/client.tcl" "прибитое" - "#729fcf" "" "" 90 &
CP=$!
wait_client "$LOG" 'прибитое'
PID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 3p)
SZ_PIN0=$(size_of "$PID")
wmctrl -i -r "$PID" -b remove,maximized_vert; sleep 1
SZ_PIN=$(size_of "$PID")

import -window root "$HERE/asusual-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/asusual-test.png"
kill $WM $CA $CR $CP 2>/dev/null

echo "--- actors: A=$AID R=$RID P=$PID (B=$B top=$TOP panel=$PH) half=$HALF"
echo "--- born $G_BORN; released $SZ_REL; back $G_BACK"
echo "--- moved $G_MOVED -> home $G_HOME; cut $G_CUT -> again $G_AGAIN -> undo $G_UNDO"
echo "--- WM said:"
grep -E 'as-usual|no longer maximized|pinned by' "$LOG"

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
expect() {   # what wanted got
    if [ "$2" = "$3" ]; then echo "OK: $1 ($3)"
    else echo "FAIL: $1 — wanted $2, got $3"; BAD=1; fi
}
case "$LABELS_A" in
    *As-Usual*) echo "FAIL: a window with no place rule grew the row: $LABELS_A"
                BAD=1 ;;
    *Rename*)   echo "OK: no place rule, no As-Usual row" ;;
    *)          echo "FAIL: the plain menu read: $LABELS_A"; BAD=1 ;;
esac
case "$LABELS_R" in
    *As-Usual*) echo "OK: the styled window carries the As-Usual row" ;;
    *)          echo "FAIL: the styled menu read: $LABELS_R"; BAD=1 ;;
esac
expect "born by 50%right: the right half at full height, flush right" \
    "400x$((WAH))+400+0" "$G_BORN"
case $ST_BORN in
    *MAXIMIZED_HORZ*) echo "FAIL: the half-width window published HORZ: $ST_BORN"
                      BAD=1 ;;
    *MAXIMIZED_VERT*) echo "OK: ...and it publishes VERT alone" ;;
    *) echo "FAIL: published state at birth: $ST_BORN"; BAD=1 ;;
esac
# The released height is the client's NATURAL one (geom "-" asked for
# nothing, so the way back is whatever the label wanted) — what must
# hold is that the axis let go and the width stayed the rule's.
RELW=${SZ_REL%x*}; RELH=${SZ_REL#*x}
expect "the release left the width the rule's" "$CW" "$RELW"
if [ "$RELH" -lt "$MAXH" ]; then
    echo "OK: the unforced rule let the client's remove release the height ($RELH < $MAXH)"
else
    echo "FAIL: after the remove the client is still $RELH tall (held at $MAXH)"; BAD=1
fi
case $ST_REL in
    *MAXIMIZED*) echo "FAIL: maximized still published after the release: $ST_REL"
                 BAD=1 ;;
    *) echo "OK: ...and VERT left the published state" ;;
esac
expect "As-Usual put it back by the rule" "400x$((WAH))+400+0" "$G_BACK"
case $ST_BACK in
    *MAXIMIZED_VERT*) echo "OK: ...and VERT is published again" ;;
    *) echo "FAIL: published state after As-Usual: $ST_BACK"; BAD=1 ;;
esac
if [ "$G_MOVED" = "$G_HOME" ]; then
    echo "FAIL: the drag did not move it, so coming home proved nothing ($G_MOVED)"
    BAD=1
else
    expect "...and brings a dragged window home" "400x$((WAH))+400+0" "$G_HOME"
fi
case $ST_CUT in
    *MAXIMIZED*) echo "FAIL: the hand resize left the mark standing: $ST_CUT"
                 BAD=1 ;;
    *) echo "OK: the hand resize shed the mark (set-maximize drop)" ;;
esac
expect "As-Usual after the cut re-places and re-marks" \
    "400x$((WAH))+400+0" "$G_AGAIN"
# The toggle lets the HELD axis go: the height comes back to what the
# pick displaced (the cut's), the width stays the rule's 50% — the
# horizontal was sized, never held, so it has no way back to travel.
expect "...and the toggle restores the height the pick displaced" \
    "400x$((WAH - 80))+400+0" "$G_UNDO"
expect "the forced rule was born at full height too" "$HALF" "$SZ_PIN0"
expect "...and a client's remove bounced off its pinned axis" "$HALF" "$SZ_PIN"
if grep -q 'pinned by place {50%right force}, refused' "$LOG"; then
    echo "OK: ...naming the rule that pinned it"
else
    echo "FAIL: no per-axis pin line in the log"; BAD=1
fi
if grep -q 'handler error\|soft failure' "$LOG"; then
    echo "FAIL: handler errors or soft failures:"
    grep 'handler error\|soft failure' "$LOG"; BAD=1
fi
check_invariants "$LOG"
if grep -q 'WM: INVARIANT' "$LOG"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: a place that fills an axis IS maximize there, and\
 As-Usual is the way back to the rule"
exit $BAD
