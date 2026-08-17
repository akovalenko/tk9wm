#!/bin/sh
# Regression for the GENERALIZED cycle (the owner's spec, 2026-08-17):
# a winlist opened by any motion-meaning chord under a still-held
# modifier runs the fvwm cycle — the invoking key's own motion at
# open, the motion letters walking while the hold lasts, commit on
# release. The acceptance bind is the owner's own: {<Super>t <Super>p}
# opens walking UP — first window straight to LAST — p/n under the
# held Super walk the list, releasing Super commits. (The exact
# <Super>p rides beside the stock bare p of the Super+t tree —
# panel-pin-last — and the exact match wins; nothing is unbound.)
#
# The chord-hold half: ONE bare-written bind ({<Super>s p}) is both
# hands (set-chord-hold on) — typed with Super held through it the
# fired action hears the physical modifier and cycles; typed released
# it hears a bare p and stands as the static menu. And the two
# boundaries of the mode: winlist-all rides the same rail (it shares
# winlist-of), while a modified chord that means NO motion
# (<Super>grave) opens the static menu — a hand that did not ask to
# cycle is not made to hold anything.
. "$(dirname "$0")/common.sh"
start_xvfb
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT

cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
wm-bind {<Super>t <Super>p} winlist "the owner's acceptance bind"
wm-bind {<Super>s p} winlist "bare-written, for the chord-hold half"
wm-bind {<Super>n} winlist-all "a motion letter on winlist-all"
wm-bind {<Super>grave} winlist "modified, but no motion"
EOF

LOG="$HERE/wm-winlistcycle.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

"$LINUX/whale" "$HERE/client.tcl" "цикл-А" 240x120 "#8ae234" "" "" 90 &
CA=$!
wait_client "$LOG" 'цикл-А'
"$LINUX/whale" "$HERE/client.tcl" "цикл-Б" 240x120 "#fcaf3e" "" "" 90 &
CB=$!
wait_client "$LOG" 'цикл-Б'
"$LINUX/whale" "$HERE/client.tcl" "цикл-В" 240x120 "#729fcf" "" "" 90 &
CC=$!
wait_client "$LOG" 'цикл-В'

key()     { xdotool key "$@"; sleep 0.5; }
keydown() { xdotool keydown "$@"; sleep 0.4; }
keyup()   { xdotool keyup "$@"; sleep 0.4; }
q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1; }

# Focus history now: В (current), Б, А — the list reads В Б А, top
# down, and every leg below re-reads it after its own commit moved it.

# ---- the acceptance bind: open walking UP, straight onto the LAST row
keydown super
key t
key p            # cycle opens; p's own -1 wraps onto the last row (А)
keyup super      # ...and the release commits it
# history: А В Б

# ---- p/n under the held Super walk the list; release commits where
# the walk stopped (p to the last row Б, n around to А, n onto В)
keydown super
key t
key p
key n
key n
keyup super      # commits the second row: В
# history: В А Б

# ---- chord-hold: the SAME bare-written bind, two hands
q 'set-chord-hold on' >/dev/null
sleep 0.5
keydown super    # the hand never lets go: Super rides through s and p
key s
key p            # fires wearing the physical Super — a cycle, onto Б
keyup super      # commits the last row: Б
# history: Б В А
key super+s      # ...and the released hand: the prefix, then a bare p
key p            # fires with nothing held — the static menu stands
key Escape
# history unmoved: Б В А

# ---- winlist-all rides the same rail: Super+n is a motion chord
keydown super
key n            # cycle; n's own +1 — the second row (В)
keyup super      # commits В
# history: В Б А

# ---- a modified chord that means no motion: static, and the release
# commits nothing
keydown super
key grave
keyup super      # no cycle was armed — nothing happens
key Escape

kill $WM $CA $CB $CC 2>/dev/null

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
AID=$1; BID=$2; CID=$3
echo "--- actors: А=$AID Б=$BID В=$CID"
echo "--- winlist lines:"
grep -E 'winlist' "$LOG"

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
CYCLES=$(grep -c 'winlist open (3 windows, cycle)' "$LOG")
if [ "$CYCLES" = "4" ]; then
    echo "OK: four cycle opens — the acceptance bind twice, the held s-p, Super+n"
else
    echo "FAIL: $CYCLES cycle opens, want 4"; BAD=1
fi
STATICS=$(grep -c 'winlist open (3 windows)$' "$LOG")
if [ "$STATICS" = "2" ]; then
    echo "OK: the released s-p hand and Super+grave both stood static"
else
    echo "FAIL: $STATICS static opens, want 2"; BAD=1
fi
PICKS=$(sed -n 's/^WM: winlist pick \(0x[0-9a-f]*\)$/\1/p' "$LOG" | tr '\n' ' ')
if [ "$PICKS" = "$AID $CID $BID $CID " ]; then
    echo "OK: picks in order — the last row at open, the p/n walk, chord-hold, winlist-all"
else
    echo "FAIL: winlist picks were «$PICKS», want «$AID $CID $BID $CID »"; BAD=1
fi
if grep -q 'handler error\|soft failure' "$LOG"; then
    echo "FAIL: handler errors or soft failures:"
    grep 'handler error\|soft failure' "$LOG"; BAD=1
fi
check_invariants "$LOG"
if grep -q 'WM: INVARIANT' "$LOG"; then BAD=1; fi
[ $BAD -eq 0 ] && echo "OK: the cycle follows the chord that called it, and only that chord"
exit $BAD
