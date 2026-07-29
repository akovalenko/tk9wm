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
export DISPLAY=:95
rm -f /tmp/.X95-lock /tmp/.X11-unix/X95
Xvfb :95 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

key() { xdotool key "$@"; sleep 1; }
state() { xprop -id "$1" WM_STATE 2>/dev/null | sed -n 's/.*window state: //p'; }

CONF="$HERE/sweep-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
wm-style {filter -title "стойкий*"} {minimize refuse}
wm-bind {<Super>z} Minimize
wm-bind {<Super>d} {Apply-To-Matching always Minimize}
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$HERE/wm-sweep.log" 2>&1 &
WM=$!
sleep 1.5

# The refuser goes up FIRST, so the focus ends on an ordinary client
# and the bare-Minimize phase measures what it means to.
"$LINUX/whale" "$HERE/client.tcl" "стойкий-C" 200x100 "#ef2929" "" "" 40 \
    > "$HERE/sweep-c.log" 2>&1 &
CC=$!
sleep 1
"$LINUX/whale" "$HERE/client.tcl" "клиент-A" 220x120 "#fce94f" "" "" 40 \
    > "$HERE/sweep-a.log" 2>&1 &
CA=$!
sleep 1
"$LINUX/whale" "$HERE/client.tcl" "клиент-B" 240x140 "#8ae234" "" "" 40 \
    > "$HERE/sweep-b.log" 2>&1 &
CB=$!
sleep 2

IDS=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-sweep.log")
CID=$(echo "$IDS" | sed -n 1p)
AID=$(echo "$IDS" | sed -n 2p)
BID=$(echo "$IDS" | sed -n 3p)
FOCUS=$(sed -n 's/^WM: focus -> \(0x[0-9a-f]*\).*/\1/p' "$HERE/wm-sweep.log" | tail -1)
echo "--- C(refuser)=$CID  A=$AID  B=$BID   focused=$FOCUS"

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

[ $BAD -eq 0 ] && echo "OK: window commands resolve context, and the sweep spares nobody it can take"
exit $BAD
