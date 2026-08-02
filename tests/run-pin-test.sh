#!/bin/sh
# Regression for PINNING THE LAST THING YOU STARTED — the keyboard
# half of populating a panel (the owner, 2026-08-02: «s-t p, pin the
# last thing I STARTED to the panel»; anything started by other means
# is pinned with the mouse).
#
# The distinction under test is the one that makes the answer a FACT
# rather than a guess: the desk remembers what IT launched, not what
# last appeared. So a press that merely found and raised an existing
# window must not change the answer — otherwise the wrong thing gets
# pinned by whoever alt-tabbed at the wrong moment.
#
#  - nothing started yet: the chord says so and writes nothing;
#  - after a launch, the chord writes an ordinary panel-button into
#    the custom layer and the strip grows one;
#  - a second press says it is already there rather than writing twice;
#  - and RAISING something does not become "the last thing started".
. "$(dirname "$0")/common.sh"
export DISPLAY=:75
rm -f /tmp/.X75-lock /tmp/.X11-unix/X75
Xvfb :75 -screen 0 800x500x24 >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
trap 'kill $XVFB 2>/dev/null; rm -rf "$CONF"' EXIT

LOG="$HERE/wm-pin.log"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
# One deed ON the panel, so the strip exists from the start, and two
# that are NOT — the ones worth pinning.
action here {launch {Run sleep 300} key {<Super>1}}
action gimpish {terminal {name gimpish} key {<Super>2}}
action other   {terminal {name otherish} key {<Super>3}}
panel-button here
EOF
sleep 1
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 2

key() { xdotool key "$@"; sleep 0.7; }
q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1; }
pin() { key super+t; key p; }
refs() { q 'lsort [dict keys [panel-cfg default refs]]'; }

# --- nothing started yet
pin
EMPTY=$(refs)
NOTHING=$(grep -c 'nothing started from here yet' "$LOG")

# --- start one, pin it
key super+2
sleep 2
STARTED=$(q 'set ::last_started')
pin
ONE=$(refs)

# --- press it AGAIN: it finds the window it already made, which is
#     not a start — and the pin must say "already there", not move on
key super+2
sleep 1
STILL=$(q 'set ::last_started')
pin
TWICE=$(refs)
ALREADY=$(grep -c 'is already on the' "$LOG")

# --- start something that is ALREADY on the strip. It launches, so
#     the launch branch runs — and it still must not become the answer,
#     because pinning it is a no-op and it would bury the thing one
#     actually wants kept (the owner, 2026-08-02).
key super+3
sleep 2
BEFOREHERE=$(q 'set ::last_started')
key super+1
sleep 2
AFTERHERE=$(q 'set ::last_started')
pin
BOTH=$(refs)
SAID=$(q 'lsort [dict keys [dict get $::layer_knobs custom]]')
kill $WM 2>/dev/null

echo "--- refs: empty «$EMPTY» one «$ONE» twice «$TWICE» both «$BOTH»"
echo "--- last started: after a launch «$STARTED», after a raise «$STILL»"
echo "--- the custom layer says: $SAID"

echo "--- verdict"
FAIL=0
want() {
    if [ "$2" = "$3" ]; then
        echo "OK: $1"
    else
        echo "FAIL: $1 — got «$2», wanted «$3»"; FAIL=1
    fi
}
want "nothing started yet: nothing is pinned"      "$EMPTY" "here"
if [ "$NOTHING" -ge 1 ]; then
    echo "OK: ...and the desk says so instead of pinning something at random"
else
    echo "FAIL: no word about there being nothing to pin"; FAIL=1
fi
want "a launch is remembered by name"              "$STARTED" "gimpish"
want "...and the chord pins it"                    "$ONE" "gimpish here"
want "RAISING is not starting — the answer does not move" "$STILL" "gimpish"
want "...and a second pin adds nothing"            "$TWICE" "gimpish here"
if [ "$ALREADY" -ge 1 ]; then
    echo "OK: ...and says it is already there"
else
    echo "FAIL: the second pin said nothing about it being there"; FAIL=1
fi
want "starting an UNPINNED deed makes it the answer" "$BEFOREHERE" "other"
want "...and starting a deed that already has an icon does NOT" \
    "$AFTERHERE" "other"
want "so the pin still lands on the thing worth keeping" \
    "$BOTH" "gimpish here other"
case "$SAID" in
    *"panel-button gimpish"*) echo "OK: written as an ordinary panel-button" ;;
    *) echo "FAIL: the custom layer holds «$SAID»"; FAIL=1 ;;
esac
if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors:"; grep 'handler error' "$LOG"; FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
