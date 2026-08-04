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
wm-bind {<Super>r} Reload
EOF
askq() {
    printf '%s\n' "$1" > "$CONF/hq.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm-ui "$CONF/hq.tcl" 2>&1
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
# ---- warm: Escape answers empty ----
key super+1
sleep 2
BOXID=$(xdotool search --class Tk9wmAsk 2>/dev/null | head -1)
BOXGEO=""
if [ -n "$BOXID" ]; then
    BOXGEO=$(xwininfo -id "$BOXID" | awk '/Absolute upper-left X/ {x=$NF}
        /Absolute upper-left Y/ {y=$NF} /Width:/ {w=$NF} /Height:/ {h=$NF}
        END {print x, y, w, h}')
fi
LAYS=$(askq 'list frow [dict get [grid info .ask.b.f] -row] \
    fcol [dict get [grid info .ask.b.f] -column]')
key Escape
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
# ---- a reload yanks the standing ask, box and all ----
key super+1
sleep 2
key super+r
sleep 2
LEFT=$(xdotool search --class Tk9wmAsk 2>/dev/null | wc -l)

import -window root "$HERE/ask-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/ask-test.png"
kill $WM $CA 2>/dev/null

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
if grep -q 'TEST: ask <>' "$LOG"; then
    echo "OK: Escape answered the empty answer"
else
    echo "FAIL: the Escape never answered"; BAD=1
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
if [ "$LAYS" = "frow 0 fcol 1" ]; then
    echo "OK: a short prompt sits beside the field"
else
    echo "FAIL: the short layout says: $LAYS"; BAD=1
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
if grep -q 'WM: ask 5: .* — the wait is cancelled' "$LOG"; then
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
