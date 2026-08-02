#!/bin/sh
# Regression: A BOUND `exec` NO LONGER STOPS THE DESK.
#
# The owner bound `exec xedit` to a chord and everything froze until
# the editor was closed (2026-08-02): a binding's script ran straight
# in the event loop, so anything synchronous in it held the whole
# desk. Scripts run in coroutines now and `exec` is shadowed — with a
# coroutine under it, the pipeline runs through the event loop and the
# script parks.
#
# So: one chord runs a slow command, and while it is still running a
# second chord must answer. And the value still comes back: `exec echo`
# in a binding returns what the child said. The config's own exec
# stays blocking (there is no coroutine there) — asserted by a config
# that execs at load and still comes up.
. "$(dirname "$0")/common.sh"
export DISPLAY=:102
rm -f /tmp/.X102-lock /tmp/.X11-unix/X102
Xvfb :102 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/coop-config"
mkdir -p "$HERE/coop-config"
cat > "$HERE/coop-config/tk9wm.tcl" <<'EOF'
set-welcome off
# the config's own exec is SYNCHRONOUS and always was — no coroutine
# stands under a layer being loaded
set atload [exec printf loaded]
puts "WM: config said $atload"
wm-bind {<Super>1} {puts "WM: slow starts"; exec sh -c {sleep 2}
    puts "WM: slow done"} slow
wm-bind {<Super>2} {puts "WM: quick answered"} quick
wm-bind {<Super>3} {puts "WM: got [exec printf hello]"} value
wm-bind {<Super>4} {exec sh -c {echo well; exit 3}} failing
EOF

XDG_CONFIG_HOME="$HERE/coop-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-coop.log" 2>&1 &
WM=$!
sleep 1.5

xdotool key super+1
sleep 0.5
xdotool key super+2      # ...while the slow one is still parked
sleep 2.5
xdotool key super+3
sleep 0.5
xdotool key super+4
sleep 1

# the ORDER is the whole point: the quick chord answered between the
# slow one starting and finishing
ORDER=$(grep -aE 'slow starts|quick answered|slow done' "$HERE/wm-coop.log" \
        | sed 's/^WM: //' | tr '\n' '|')
VALUE=$(grep -ac 'WM: got hello' "$HERE/wm-coop.log" || true)
LOADED=$(grep -ac 'WM: config said loaded' "$HERE/wm-coop.log" || true)
FAILED=$(grep -aci 'well' "$HERE/wm-coop.log" || true)

kill $WM 2>/dev/null
sleep 0.5

echo "--- order: $ORDER"
echo "--- value=$VALUE config-exec=$LOADED failure-noted=$FAILED"
echo "--- verdict"
if [ "$ORDER" = "slow starts|quick answered|slow done|" ]; then
    echo "OK: the desk answered another chord while a bound exec was running"
else
    echo "FAIL: the order was «$ORDER»"
fi
if [ "$VALUE" = 1 ]; then
    echo "OK: a cooperative exec still returns what the child said"
else
    echo "FAIL: exec's value did not come back"
fi
if [ "$LOADED" = 1 ]; then
    echo "OK: the config's own exec is synchronous, and the desk came up"
else
    echo "FAIL: the config's exec at load ($LOADED)"
fi
if [ "$FAILED" -ge 1 ]; then
    echo "OK: a non-zero exit is a failure, and what the child said is in it"
else
    echo "FAIL: the failing exec said nothing ($FAILED)"
fi
check_invariants "$HERE/wm-coop.log"
