#!/bin/sh
# Regression for Ask — a line of text from the person, dressed as the
# desk.
#
# The word spawns the ui host when none is up, parks a coroutine, and
# the box that appears is undecorated, standing at the place-grammar
# point, with no buttons: typing and Enter answer the waiting script,
# Escape answers empty. A reload yanks a standing ask — the waiter is
# cancelled under its own name and the box is told to go.
. "$(dirname "$0")/common.sh"
export DISPLAY=:109
rm -f /tmp/.X109-lock /tmp/.X11-unix/X109
Xvfb :109 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

key() { xdotool key "$@"; sleep 1; }
LOG="$HERE/wm-ask.log"

CONF="$HERE/ask-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
wm-bind {<Super>1} {puts "TEST: ask <[Ask "спроси:" -place {hcenter bottom}]>"}
wm-bind {<Super>2} {puts "TEST: ask2 <[Ask "и это очень длинный вопрос юзеру про всё"]>"}
wm-bind {<Super>3} {puts "TEST: ask3 <[Ask "полширины:" -width 50%]>"}
wm-bind {<Super>4} {puts "TEST: chain <[Ask "первый:"]|[Ask "второй:"]>"}
wm-bind {<Super>r} Reload
EOF
askq() {
    printf '%s\n' "$1" > "$CONF/hq.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm-ui "$CONF/hq.tcl" 2>&1
}
px() {
    import -window root png:- 2>/dev/null | convert png:- -format \
        "%[pixel:p{$1,$2}]" info:-
}

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "аск-окно" 240x120 "#fce94f" "" "" 90 \
    > "$HERE/ask-c.log" 2>&1 &
CA=$!
sleep 2

# ---- cold: the host is spawned, the box answers the typing ----
key super+1
sleep 5                    # a fresh host loads a Tk and a theme
xdotool type hello42
sleep 1
key Return
sleep 1
# ---- warm: Escape CANCELS the asking script ----
key super+1
sleep 2
BOXID=$(xdotool search --class Tk9wmGadget 2>/dev/null | head -1)
BOXGEO=""
if [ -n "$BOXID" ]; then
    BOXGEO=$(xwininfo -id "$BOXID" | awk '/Absolute upper-left X/ {x=$NF}
        /Absolute upper-left Y/ {y=$NF} /Width:/ {w=$NF} /Height:/ {h=$NF}
        END {print x, y, w, h}')
fi
LAYS=$(askq 'list frow [dict get [grid info .ask.b.f] -row] \
    fcol [dict get [grid info .ask.b.f] -column] \
    title [wm title .ask]')
key Escape
sleep 1
# ---- an empty Enter is an answer, the empty one ----
key super+1
sleep 2
key Return
sleep 1
# ---- a long prompt sits ABOVE the field, on the echo's amber ----
key super+2
sleep 2
LAYL=$(askq 'list prow [dict get [grid info .ask.b.p] -row] \
    frow [dict get [grid info .ask.b.f] -row] \
    modal [expr {[.ask.b cget -background] eq [ui-color modal]}]')
key Escape
sleep 1
# ---- a said width, in percent of the workarea ----
key super+3
sleep 2
WIDE=$(askq 'winfo width .ask')
key Escape
sleep 1
# ---- two asks in one script: the second must run too ----
key super+4
sleep 2
xdotool type one
sleep 1
key Return
sleep 1
xdotool type two
sleep 1
key Return
sleep 1
# ---- a menu over a standing ask must not kill it ----
key super+1
sleep 2
key alt+space
key Escape
xdotool type stillhere
sleep 1
key Return
sleep 1
# ---- a newer ask displaces the older, and says so ----
key super+1
sleep 2
key super+2
sleep 2
xdotool type disp
sleep 1
key Return
sleep 1
# ---- a fresh window rising over the ask neither hides it, nor
#      kills it, nor even takes the typing: the focus is the ask's,
#      and the newcomer gets it AFTER the answer
key super+1
sleep 2
set -- $BOXGEO
"$LINUX/whale" "$HERE/client.tcl" "поверх-окно" 240x100+190+530 "#8ae234" "" "" 60 \
    > "$HERE/ask-r.log" 2>&1 &
CR=$!
sleep 2
ONTOP=$(px $(($1 + 6)) $(($2 + 6)))
xdotool type ontop     # no tabbing back: the focus never left the box
sleep 1
key Return
sleep 1
# ---- but alt-tabbing AWAY from the box is answering nothing ----
key super+1
sleep 2
key alt+Tab
sleep 1
# ---- a reload yanks the standing ask, box and all ----
key super+1
sleep 2
key super+r
sleep 2
LEFT=$(xdotool search --class Tk9wmGadget 2>/dev/null | wc -l)

import -window root "$HERE/ask-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/ask-test.png"
kill $WM $CA $CR 2>/dev/null

echo "--- box: id=$BOXID geo=($BOXGEO) left-after-yank=$LEFT"
echo "--- WM saw:"
grep -E 'TEST: ask|WM: Ask|WM: ask ' "$LOG"

echo "--- verdict"
BAD=0
if grep -q 'soft failure\|handler error' "$LOG"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$LOG"; BAD=1
fi
if grep -q 'TEST: ask <hello42>' "$LOG"; then
    echo "OK: the typed line came back to the waiting script"
else
    echo "FAIL: the answer never reached the asker"; BAD=1
fi
if grep -q 'WM: ask [0-9]*: cancelled by the person' "$LOG" \
        && grep -q 'cancelled — .*the person cancelled the ask' "$LOG"; then
    echo "OK: Escape cancelled the ask, and the script stopped quietly"
else
    echo "FAIL: the Escape cancel is missing or loud"; BAD=1
fi
if grep -q 'TEST: ask <>' "$LOG"; then
    echo "OK: an empty Enter delivered the empty string"
else
    echo "FAIL: the empty answer never arrived"; BAD=1
fi
if grep -q 'WM: PROBLEM' "$LOG"; then
    echo "FAIL: a deliberate cancel was recorded as a problem:"
    grep 'WM: PROBLEM' "$LOG"; BAD=1
else
    echo "OK: not one cancel nagged the problems store"
fi
if [ -n "$BOXGEO" ]; then
    set -- $BOXGEO
    X=$1; Y=$2; W=$3; H=$4
    MID=$((X + W / 2))
    BOT=$((Y + H))
    if [ $BOT -ge 590 ] && [ $BOT -le 600 ] \
            && [ $MID -ge 370 ] && [ $MID -le 430 ]; then
        echo "OK: the box stood at its place — hcenter bottom ($BOXGEO)"
    else
        echo "FAIL: the box stood at ($BOXGEO), want bottom center"; BAD=1
    fi
else
    echo "FAIL: no Tk9wmAsk box found on the second ask"; BAD=1
fi
if [ "$LAYS" = "frow 0 fcol 1 title спроси:" ]; then
    echo "OK: a short prompt sits beside the field, and the box is titled"
else
    echo "FAIL: the short layout says: $LAYS"; BAD=1
fi
if grep -q 'on layer 10' "$LOG"; then
    echo "OK: the gadget rule put the box above the top client layer"
else
    echo "FAIL: the box never landed on layer 10"; BAD=1
fi
if [ "$LAYL" = "prow 0 frow 1 modal 1" ]; then
    echo "OK: a long prompt sits above the field, on the echo's own amber"
else
    echo "FAIL: the long layout says: $LAYL"; BAD=1
fi
if [ "$WIDE" = "400" ]; then
    echo "OK: -width 50% made the box half the workarea wide"
else
    echo "FAIL: the 50% box is $WIDE px wide, want 400"; BAD=1
fi
if grep -q 'TEST: chain <one|two>' "$LOG"; then
    echo "OK: two asks in one script both ran, in order"
else
    echo "FAIL: the chained asks broke"; BAD=1
fi
if grep -q 'TEST: ask <stillhere>' "$LOG"; then
    echo "OK: a menu opened and closed over a standing ask did not kill it"
else
    echo "FAIL: the menu hand-over killed the standing ask"; BAD=1
fi
if grep -q 'displaced by a newer ask' "$LOG" \
        && grep -q 'TEST: ask2 <disp>' "$LOG"; then
    echo "OK: a newer ask displaced the older, said so, and got its answer"
else
    echo "FAIL: the displacement is silent or the newer ask broke"; BAD=1
fi
RID=$(sed -n 's/^WM: title \(0x[0-9a-f]*\) -> «поверх-окно».*/\1/p' "$LOG" | head -1)
AFTERFOCUS=$(sed -n '/TEST: ask <ontop>/,$p' "$LOG" | sed -n 's/^WM: focus -> \(0x[0-9a-f]*\).*/\1/p' | head -1)
if [ "$ONTOP" = "srgb(193,125,17)" ] && grep -q 'TEST: ask <ontop>' "$LOG" \
        && grep -q 'the focus is the ask'\''s — taken for later' "$LOG"; then
    echo "OK: a riser neither covered the ask nor took its typing"
else
    echo "FAIL: box pixel $ONTOP, or the answer broke, or the riser stole"; BAD=1
fi
if [ -n "$RID" ] && [ "$AFTERFOCUS" = "$RID" ]; then
    echo "OK: ...and the answer landed the focus on the riser, as its manage would have"
else
    echo "FAIL: after the answer the focus went to «$AFTERFOCUS», want the riser $RID"; BAD=1
fi
if grep -q 'WM: ask [0-9]*: the focus left the ask — the wait is cancelled' "$LOG"; then
    echo "OK: alt-tabbing away from the box answered nothing, by hand"
else
    echo "FAIL: leaving the box by hand cancelled nothing"; BAD=1
fi
if grep -q 'WM: ask [0-9]*: the config is being reloaded — the wait is cancelled' "$LOG"; then
    echo "OK: the reload cancelled the standing wait under its own name"
else
    echo "FAIL: the yank never spoke"; BAD=1
fi
if [ "$LEFT" = "0" ]; then
    echo "OK: ...and the box was told to go"
else
    echo "FAIL: $LEFT ask box(es) still stand after the yank"; BAD=1
fi

check_invariants "$LOG"
if grep -q 'WM: INVARIANT' "$LOG"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the desk asks, the person answers, the reload takes it back"
exit $BAD
