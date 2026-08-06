#!/bin/sh
# Regression for the CALM restart: releasing the desk and adopting it
# back must not be a per-window ceremony. Before the cure (2026-08-06)
# a restart released frames in hash order (shuffling the stacking the
# next instance then read back), handed the focus to doomed windows
# mid-teardown, reframed bottom-up with a raise and a focus apiece —
# nine focus transitions for eight windows, the last arrival keeping
# the highlight — and flashed the minimized window once on its way
# back off the screen.
#
# Now: released bottom-first (the tree keeps the old order), adopted
# topmost-first with each frame seated under the one before, frames
# born withdrawn and shown only dressed, ONE focus transition for the
# whole affair — back to the window that was active. Asserted against
# both truths: the model's _NET_CLIENT_LIST_STACKING and the server's
# own tree.
. "$(dirname "$0")/common.sh"
export DISPLAY=:114
rm -f /tmp/.X114-lock /tmp/.X11-unix/X114
Xvfb :114 -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

CONF="$HERE/restartcalm-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
EOF
LOG="$HERE/wm-restartcalm.log"
askw() {
    printf '%s\n' "$1" > "$CONF/q.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1
}
stacking() {
    xprop -root _NET_CLIENT_LIST_STACKING | sed 's/.*# //; s/,//g'
}

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5

i=0
for col in '#fce94f' '#8ae234' '#729fcf' '#ad7fa8' '#fcaf3e' '#e9b96e' '#ef2929' '#888a85'; do
    i=$((i+1))
    "$LINUX/whale" "$HERE/client.tcl" "окно-$i" 300x200 "$col" "" "" 120 \
        > /dev/null 2>&1 &
    sleep 0.4
done
sleep 1.5
IDS=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
W4=$(echo "$IDS" | sed -n 4p)
W6=$(echo "$IDS" | sed -n 6p)
askw "Minimize [expr {$W4}]" >/dev/null
sleep 0.5
wmctrl -i -a "$W6"
sleep 0.7
STACK0=$(stacking)
ACT0=$(xprop -root _NET_ACTIVE_WINDOW | sed 's/.*# //')
N=$(wc -l < "$LOG")
askw 'after 100 restart-wm; set _ ok' >/dev/null
sleep 6
STACK1=$(stacking)
ACT1=$(xprop -root _NET_ACTIVE_WINDOW | sed 's/.*# //')
FOCVIS=$(xwininfo -id "$W6" | sed -n 's/.*Map State: //p')
MINVIS=$(xwininfo -id "$W4" | sed -n 's/.*Map State: //p')
MINSTATE=$(xprop -id "$W4" _NET_WM_STATE | sed 's/.*= //')
# The server's own answer, top first: the frames' order read off the
# tree, translated back to the clients they hold.
GLASS=$(xwininfo -root -tree | grep -oE '0x[0-9a-f]+' | while read x; do
    echo "$IDS" | grep -ix "$x"
done | tr '\n' ' ')
TAIL=$(tail -n +$((N+1)) "$LOG")
FOCN=$(printf '%s\n' "$TAIL" | grep -c 'WM: focus ->')

import -window root "$HERE/restartcalm-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/restartcalm-test.png"
kill $WM 2>/dev/null

# the minimized window sits in neither stacking (it is off the screen
# and, adopted iconic, not yet in the model's order) — compare the rest
S0=$(echo "$STACK0" | tr ' ' '\n' | grep -iv "^$W4\$" | tr '\n' ' ')
S1=$(echo "$STACK1" | tr ' ' '\n' | grep -iv "^$W4\$" | tr '\n' ' ')
GT=$(echo "$GLASS" | tr ' ' '\n' | grep -iv "^$W4\$" | grep . | tr '\n' ' ')
# the model is bottom-first, the tree top-first
SREV=$(echo "$S1" | tr ' ' '\n' | grep . | tac | tr '\n' ' ')
echo "--- ids: $(echo $IDS | tr '\n' ' ')"
echo "--- min=$W4 act=$W6"
echo "--- stacking before: $S0"
echo "--- stacking after:  $S1"
echo "--- glass top-first: $GT"
echo "--- active: $ACT0 -> $ACT1; focus transitions after restart: $FOCN"
echo "--- restart tail:"
printf '%s\n' "$TAIL" | grep -E 'restart|adoption settled|REFUSED|focus ->' | head -8

echo "--- verdict"
BAD=0
if printf '%s\n' "$TAIL" | grep -q 'soft failure\|handler error'; then
    echo "FAIL: soft failures or handler errors:"
    printf '%s\n' "$TAIL" | grep 'soft failure\|handler error'; BAD=1
fi
if [ "$S0" = "$S1" ] && [ -n "$S0" ]; then
    echo "OK: the stacking order survived the restart"
else
    echo "FAIL: stacking before «$S0» after «$S1»"; BAD=1
fi
if [ "$GT" = "$SREV" ] && [ -n "$GT" ]; then
    echo "OK: ...and the server's tree agrees with the model"
else
    echo "FAIL: glass «$GT», model top-first «$SREV»"; BAD=1
fi
if [ "$ACT0" = "$ACT1" ] && [ "$ACT1" = "$(echo "$W6" | tr 'A-F' 'a-f')" -o "$ACT1" = "$W6" ]; then
    echo "OK: the active window came back active ($ACT1)"
else
    echo "FAIL: active was $ACT0 ($W6), after restart $ACT1"; BAD=1
fi
if [ "$FOCN" = "1" ]; then
    echo "OK: one focus transition for the whole restart"
else
    echo "FAIL: $FOCN focus transitions after restart, want 1"; BAD=1
fi
if printf '%s\n' "$TAIL" | grep -q 'adoption settled — focus back'; then
    echo "OK: ...and it is the settle, aimed at the old active"
else
    echo "FAIL: no 'adoption settled — focus back' line"; BAD=1
fi
if [ "$FOCVIS" = "IsViewable" ]; then
    echo "OK: the adopted windows are on the glass ($FOCVIS)"
else
    echo "FAIL: the active window's map state is «$FOCVIS»"; BAD=1
fi
case "$MINVIS" in
    IsUnMapped|IsUnviewable)
        echo "OK: the minimized window stayed off the screen ($MINVIS)" ;;
    *) echo "FAIL: the minimized window's map state is «$MINVIS»"; BAD=1 ;;
esac
case "$MINSTATE" in
    *_NET_WM_STATE_HIDDEN*)
        echo "OK: ...and still publishes HIDDEN" ;;
    *) echo "FAIL: the minimized window's state reads: $MINSTATE"; BAD=1 ;;
esac
if printf '%s\n' "$TAIL" | grep -q 'REFUSED by server'; then
    echo "FAIL: a focus was refused during the restart:"
    printf '%s\n' "$TAIL" | grep 'REFUSED'; BAD=1
else
    echo "OK: no focus was refused along the way"
fi

check_invariants "$LOG"
if grep -q 'WM: INVARIANT' "$LOG"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the restart is one breath, not a ceremony per window"
exit $BAD
