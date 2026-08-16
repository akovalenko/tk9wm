#!/bin/sh
# Regression for Rename — the person's word over the desk's:
#
#   бокс     Rename stands the ask box ON the window — under its own
#            titlebar, spanning the frame — primed with the VISIBLE
#            title (what you see is what you edit); Escape changes
#            nothing and nags nobody
#   слово    a typed word outranks a style-said `title`, and the
#            client renaming itself does not budge it
#   шаблон   the answer is a template: «п: %t» is a live prefix whose
#            tail follows the client's renames; «%t» shows the raw
#            words THROUGH a standing style rule — and since shown
#            then equals the client's own, _NET_WM_VISIBLE_NAME goes
#   пусто    the empty answer takes the hand rename off — back to the
#            style rule (the kitty reading of an emptied field)
#   рты      the winops row fires it on `e`; a programmatic sweep is
#            refused with a line and no box
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1; }
LOG="$HERE/wm-rename.log"
CONF="$HERE/rename-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
wm-style {filter -title {рен *}} {title {стиль: %t}}
wm-bind {<Super>1} Rename
wm-bind {<Super>2} {Apply-To-Matching always Rename}
EOF

askw() {   # eval in the WM
    printf '%s\n' "$1" > "$CONF/q.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1
}
askq() {   # eval in the ui host
    printf '%s\n' "$1" > "$CONF/hq.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm-ui "$CONF/hq.tcl" 2>&1
}
sendc() {  # eval in the client
    printf '%s\n' "$1" > "$CONF/c.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" renamec "$CONF/c.tcl" 2>&1
}
box_up()   { [ -n "$(xdotool search --class Tk9wmGadget 2>/dev/null)" ]; }
box_gone() { [ -z "$(xdotool search --class Tk9wmGadget 2>/dev/null)" ]; }
vname_is()     { xprop -id "$1" _NET_WM_VISIBLE_NAME | grep -qF "= \"$2\""; }
vname_absent() { xprop -id "$1" _NET_WM_VISIBLE_NAME | grep -q 'not found'; }
check_name() {  # label id want — poll, then say what actually stands
    if wait_for 10 vname_is "$2" "$3"; then
        echo "OK: $1 — «$3»"
    else
        echo "FAIL: $1 — want «$3», got: $(xprop -id "$2" _NET_WM_VISIBLE_NAME)"
    fi
}

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

"$LINUX/whale" "$HERE/client-rename.tcl" > "$HERE/rename-c.log" 2>&1 &
CA=$!
wait_client "$LOG" 'рен старт'
WID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | head -1)
echo "--- actor: $WID"

# ---- the box: primed with the visible title, under the titlebar ----
key super+1
wait_for 20 box_up          # the first ask spawns the ui host
PRIMED=$(askq 'list init [ui-field-get .ask.b.f] title [wm title .ask]')
BOXID=$(xdotool search --class Tk9wmGadget 2>/dev/null | head -1)
BOXGEO=""
if [ -n "$BOXID" ]; then
    BOXGEO=$(xwininfo -id "$BOXID" | awk '/Absolute upper-left X/ {x=$NF}
        /Absolute upper-left Y/ {y=$NF} /Width:/ {w=$NF}
        END {print x, y, w}')
fi
# the log's id is hex, the WM's array keys are decimal — normalize
EXPGEO=$(askw "set w [expr {$WID + 0}]
lassign [frame-rect \$w] fx fy fw fh
list \$fx [expr {\$fy + [lindex [chrome-of \$w] 1]}] \$fw")
# ---- ...and Escape walks away without a mark ----
key Escape
wait_for 10 box_gone

# ---- a typed word outranks the style rule ----
key super+1
wait_for 10 box_up
askq 'ui-field-set .ask.b.f {моё окно}'
key Return
check_name "the person's word replaced the style title" "$WID" "моё окно"
# ---- ...and the client renaming itself does not budge it ----
sendc 'wm title . {рен второй}'
wait_client "$LOG" 'рен второй'
check_name "a literal rename ignores the client's hop" "$WID" "моё окно"

# ---- the answer is a template: a live prefix follows the client ----
key super+1
wait_for 10 box_up
PRIMED2=$(askq 'ui-field-get .ask.b.f')
askq 'ui-field-set .ask.b.f {п: %t}'
key Return
check_name "a %t template took the current tail" "$WID" "п: рен второй"
sendc 'wm title . {рен третий}'
wait_client "$LOG" 'рен третий'
check_name "...and the tail follows the client's rename" "$WID" "п: рен третий"

# ---- «%t» bares the client's words through the style rule ----
key super+1
wait_for 10 box_up
askq 'ui-field-set .ask.b.f {%t}'
key Return
if wait_for 10 vname_absent "$WID"; then
    echo "OK: «%t» shows the raw words — shown equals the client's, the property goes"
else
    echo "FAIL: «%t» — $(xprop -id "$WID" _NET_WM_VISIBLE_NAME)"
fi
BARED=$(askw "set w [expr {$WID + 0}]
list vis [visible-title \$w] layer \$::renameof(\$w)")
# ---- the empty answer takes the rename off, the style rule returns ----
key super+1
wait_for 10 box_up
askq 'ui-field-set .ask.b.f {}'
key Return
check_name "the emptied field went back to the style title" \
    "$WID" "стиль: рен третий"
LAYER=$(askw "info exists ::renameof([expr {$WID + 0}])")

# ---- a programmatic sweep is refused with a line and no box ----
wait_for 10 box_gone
key super+2
sleep 2
SWEPT=$(xdotool search --class Tk9wmGadget 2>/dev/null | wc -l)

# ---- the winops row fires it on `e` ----
key alt+space
key e
wait_for 10 box_up
PRIMED3=$(askq 'ui-field-get .ask.b.f')
key Escape
wait_for 10 box_gone

import -window root "$HERE/rename-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/rename-test.png"
kill $WM $CA 2>/dev/null

echo "--- box: geo=($BOXGEO) want=($EXPGEO)"
echo "--- WM saw:"
grep -E 'WM: Ask|WM: ask |WM: Rename' "$LOG"

echo "--- verdict"
BAD=0
if grep -q 'soft failure\|handler error' "$LOG"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$LOG"; BAD=1
fi
if [ "$PRIMED" = "init {стиль: рен старт} title Rename" ]; then
    echo "OK: the box came primed with the VISIBLE title, and says Rename"
else
    echo "FAIL: the first box says: $PRIMED"; BAD=1
fi
if [ -n "$BOXGEO" ] && [ "$BOXGEO" = "$EXPGEO" ]; then
    echo "OK: the box stood under the titlebar, spanning the frame"
else
    echo "FAIL: the box stood at ($BOXGEO), want ($EXPGEO)"; BAD=1
fi
if grep -q 'WM: ask [0-9]*: cancelled by the person' "$LOG"; then
    echo "OK: Escape cancelled the ask"
else
    echo "FAIL: the Escape cancel never spoke"; BAD=1
fi
if grep -q 'WM: PROBLEM' "$LOG"; then
    echo "FAIL: a deliberate cancel was recorded as a problem:"
    grep 'WM: PROBLEM' "$LOG"; BAD=1
else
    echo "OK: not one cancel nagged the problems store"
fi
if [ "$PRIMED2" = "моё окно" ]; then
    echo "OK: the second box came primed with the standing rename"
else
    echo "FAIL: the second box says: «$PRIMED2»"; BAD=1
fi
if [ "$BARED" = "vis {рен третий} layer %t" ]; then
    echo "OK: the «%t» layer stands, and the desk shows the raw words"
else
    echo "FAIL: the «%t» state says: $BARED"; BAD=1
fi
if [ "$LAYER" = "0" ]; then
    echo "OK: the empty answer swept the rename layer away"
else
    echo "FAIL: ::renameof still stands after the empty answer"; BAD=1
fi
if grep -q 'WM: Rename 0x[0-9a-f]*: an interactive command' "$LOG" \
        && [ "$SWEPT" = "0" ]; then
    echo "OK: the sweep was refused with a line, and no box stood"
else
    echo "FAIL: the sweep refusal is silent, or a box stood ($SWEPT)"; BAD=1
fi
if [ "$PRIMED3" = "стиль: рен третий" ]; then
    echo "OK: the winops row fired the same ask on «e»"
else
    echo "FAIL: the winops box says: «$PRIMED3»"; BAD=1
fi

check_invariants "$LOG"
if grep -q 'WM: INVARIANT' "$LOG"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the person names the window, and takes the name back"
exit $BAD
