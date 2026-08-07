#!/bin/sh
# Regression for window commands and the sweep over them.
#
# One definition of Minimize has to serve two callers, and this proves
# both from the same config:
#
#   wm-bind {<Super>z} Minimize                 -> the ACTIVE window
#   wm-bind {<Super>d} {Apply-To-Matching always Minimize}
#                                               -> every window it can
#
# The bare form must take its window from context and touch nothing
# else — that is the whole point of binding a verb rather than a script
# that names a window. The sweep must be "as many as possible": a
# client whose style refuses minimization stays up, and its refusal
# does not cost the windows after it in the list.
#
# The refuser is singled out by title, so all three clients can be the
# same fixture and the only difference between them is the one the
# style rule sees.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1; }
state() { xprop -id "$1" WM_STATE 2>/dev/null | sed -n 's/.*window state: //p'; }

CONF="$HERE/sweep-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
wm-style {filter -title "стойкий*"} {minimize refuse}
wm-bind {<Super>z} Minimize
wm-bind {<Super>d} {Apply-To-Matching always Minimize}
# The interactive/programmatic split: pressing Super+m myself toggles,
# a sweep forces. Both spellings of Maximize, one name.
wm-bind {<Super>m} Maximize
wm-bind {<Super>x} {Apply-To-Matching always Maximize}
wm-bind {<Super>u} {Apply-To-Matching always Unmaximize}
# The desk commands, whose lowercase originals stay as implementations.
wm-bind {<Super>r} Reload
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$HERE/wm-sweep.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-sweep.log" $WM

# The refuser goes up FIRST, so the focus ends on an ordinary client
# and the bare-Minimize phase measures what it means to.
"$LINUX/whale" "$HERE/client.tcl" "стойкий-C" 200x100 "#ef2929" "" "" 40 \
    > "$HERE/sweep-c.log" 2>&1 &
CC=$!
wait_client "$HERE/wm-sweep.log" 'стойкий-C'
"$LINUX/whale" "$HERE/client.tcl" "клиент-A" 220x120 "#fce94f" "" "" 40 \
    > "$HERE/sweep-a.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-sweep.log" 'клиент-A'
"$LINUX/whale" "$HERE/client.tcl" "клиент-B" 240x140 "#8ae234" "" "" 40 \
    > "$HERE/sweep-b.log" 2>&1 &
CB=$!
wait_client "$HERE/wm-sweep.log" 'клиент-B'

IDS=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-sweep.log")
CID=$(echo "$IDS" | sed -n 1p)
AID=$(echo "$IDS" | sed -n 2p)
BID=$(echo "$IDS" | sed -n 3p)
FOCUS=$(sed -n 's/^WM: focus -> \(0x[0-9a-f]*\).*/\1/p' "$HERE/wm-sweep.log" | tail -1)
echo "--- C(refuser)=$CID  A=$AID  B=$BID   focused=$FOCUS"

# ---- phase 0: the user toggles, the program does not ----
# One name, two mouths. Pressed by hand, Maximize is a toggle, so two
# presses end where they started. Driven by a sweep it FORCES, so a
# second sweep must leave the desk maximized rather than undoing the
# first — the failure that makes a toggling sweep worthless: its result
# would depend on the state it happened to find, per window.
geom() { xwininfo -id "$1" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}'; }
G0=$(geom "$BID")
key super+m
GM=$(geom "$BID")
key super+m
G1=$(geom "$BID")
echo "--- Super+m by hand: $G0 -> $GM -> $G1"
A0=$(geom "$AID")
key super+x
SX1=$(geom "$AID")
key super+x
SX2=$(geom "$AID")
echo "--- sweep Maximize twice: $A0 -> $SX1 -> $SX2"
key super+u
SU=$(geom "$AID")
echo "--- sweep Unmaximize:    $SU (was $A0)"

# ---- phase 1: the bare verb, on whatever is active ----
key super+z
C1=$(state "$CID"); A1=$(state "$AID"); B1=$(state "$BID")
echo "--- after bare Minimize: C=$C1 A=$A1 B=$B1"

# ---- phase 2: the sweep ----
key super+d
sleep 1
C2=$(state "$CID"); A2=$(state "$AID"); B2=$(state "$BID")
echo "--- after the sweep:     C=$C2 A=$A2 B=$B2"
import -window root "$HERE/sweep-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/sweep-test.png"
SWEEP=$(grep 'Apply-To-Matching' "$HERE/wm-sweep.log" | tail -1)
# Last, because it resets everything the config built: the desk command
# Reload, reached by its new Capitalized name.
key super+r
RELOADED=$(grep -c 'config reload requested' "$HERE/wm-sweep.log")
kill $WM $CA $CB $CC 2>/dev/null

echo "--- WM saw:"
grep -E 'iconif|refus|Apply-To-Matching|Minimize' "$HERE/wm-sweep.log"

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$HERE/wm-sweep.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
if grep -q 'soft failure\|handler error' "$HERE/wm-sweep.log"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$HERE/wm-sweep.log"; BAD=1
fi

# The user's Maximize is a toggle: it grew, then came back.
if [ "$GM" != "$G0" ] && [ "$G1" = "$G0" ]; then
    echo "OK: pressed by hand, Maximize toggled ($G0 -> $GM -> $G1)"
else
    echo "FAIL: by-hand Maximize went $G0 -> $GM -> $G1, wanted out and back"
    BAD=1
fi
# The program's Maximize forces: twice in a row is still maximized.
if [ "$SX1" != "$A0" ] && [ "$SX1" = "$SX2" ]; then
    echo "OK: swept twice, Maximize forced rather than toggled ($SX1 both times)"
else
    echo "FAIL: sweeping Maximize twice went $A0 -> $SX1 -> $SX2, wanted it to stay"
    BAD=1
fi
if [ "$SU" = "$A0" ]; then
    echo "OK: the Unmaximize sweep put the desk back ($SU)"
else
    echo "FAIL: after the Unmaximize sweep the window is $SU, want $A0"; BAD=1
fi

# The bare verb took the FOCUSED window out of context, and only it.
if [ "$FOCUS" = "$BID" ] && [ "$B1" = "Iconic" ] \
        && [ "$A1" = "Normal" ] && [ "$C1" = "Normal" ]; then
    echo "OK: bare Minimize took the active window from context, and only it"
else
    echo "FAIL: bare Minimize left C=$C1 A=$A1 B=$B1 (focused was $FOCUS, B is $BID)"
    BAD=1
fi

# The sweep reached the rest; the refuser is still standing.
if [ "$A2" = "Iconic" ] && [ "$B2" = "Iconic" ]; then
    echo "OK: the sweep minimized every window that would go"
else
    echo "FAIL: after the sweep A=$A2 B=$B2, want both Iconic"; BAD=1
fi
if [ "$C2" = "Normal" ] && grep -q 'iconify refused' "$HERE/wm-sweep.log"; then
    echo "OK: the refusing client stayed up, and said so"
else
    echo "FAIL: the refuser is $C2 (want Normal) or never refused aloud"; BAD=1
fi

# A refusal in the middle must not cost the windows after it: the
# refuser is FIRST in the MRU snapshot's tail, so a sweep that aborted
# on it would leave A alone — which the check above would catch — but
# assert the count too, so the reason is visible in the output.
case "$SWEEP" in
    *"Minimize: 3 of 3 matched") echo "OK: all three matched and were tried ($SWEEP)" ;;
    *) echo "FAIL: sweep reported «$SWEEP», want 3 of 3 matched"; BAD=1 ;;
esac

if [ "$RELOADED" = "1" ]; then
    echo "OK: the desk command Reload answered to its new name"
else
    echo "FAIL: Reload fired $RELOADED times, want 1"; BAD=1
fi

[ $BAD -eq 0 ] && echo "OK: window commands resolve context, and the sweep spares nobody it can take"
exit $BAD
