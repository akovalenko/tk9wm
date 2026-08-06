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
#
# And a switch is not a trapdoor: a second exec shim once sent any
# switch-bearing line to the blocking form, so `Exec -ignorestderr`
# stopped the desk — the very thing Exec promises never to do. The
# keyed scene parks a slow `Exec -ignorestderr`, answers another
# chord meanwhile, and still gets the value with the noise ignored.
#
# Redirections ride along too (the owner's word, 2026-08-07): the
# routed scene parks a pipeline that routes its own stderr
# (`2>/dev/null | tr …`) — the words go through as they stand,
# nothing falls back to the blocking form, and a stream the line
# already routed is no error.
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
wm-bind {<Super>5} {puts "WM: keyed starts"
    puts "WM: keyed said [Exec -ignorestderr sh -c {sleep 2; echo noise >&2; printf order}]"
    puts "WM: keyed done"} keyed
wm-bind {<Super>6} {puts "WM: nimble answered"} nimble
wm-bind {<Super>7} {puts "WM: routed starts"
    puts "WM: routed said [exec sh -c {sleep 2; echo loud >&2; printf quiet} 2>/dev/null | tr a-z A-Z]"
    puts "WM: routed done"} routed
wm-bind {<Super>8} {puts "WM: eager answered"} eager
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
xdotool key super+5
sleep 0.5
xdotool key super+6      # ...while the keyed one is still parked
sleep 2.5
xdotool key super+7
sleep 0.5
xdotool key super+8      # ...while the routed one is still parked
sleep 2.5

# the ORDER is the whole point: the quick chord answered between the
# slow one starting and finishing
ORDER=$(grep -aE 'slow starts|quick answered|slow done' "$HERE/wm-coop.log" \
        | sed 's/^WM: //' | tr '\n' '|')
VALUE=$(grep -ac 'WM: got hello' "$HERE/wm-coop.log" || true)
LOADED=$(grep -ac 'WM: config said loaded' "$HERE/wm-coop.log" || true)
FAILED=$(grep -aci 'well' "$HERE/wm-coop.log" || true)
ORDER2=$(grep -aE 'keyed starts|nimble answered|keyed done' "$HERE/wm-coop.log" \
        | sed 's/^WM: //' | tr '\n' '|')
KEYED=$(grep -ac 'WM: keyed said order' "$HERE/wm-coop.log" || true)
ORDER3=$(grep -aE 'routed starts|eager answered|routed done' "$HERE/wm-coop.log" \
        | sed 's/^WM: //' | tr '\n' '|')
ROUTED=$(grep -ac 'WM: routed said QUIET' "$HERE/wm-coop.log" || true)

kill $WM 2>/dev/null
sleep 0.5

echo "--- order: $ORDER"
echo "--- keyed order: $ORDER2"
echo "--- routed order: $ORDER3"
echo "--- value=$VALUE config-exec=$LOADED failure-noted=$FAILED keyed=$KEYED routed=$ROUTED"
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
if [ "$ORDER2" = "keyed starts|nimble answered|keyed done|" ]; then
    echo "OK: a switch is no trapdoor — Exec -ignorestderr parks too"
else
    echo "FAIL: the keyed order was «$ORDER2»"
fi
if [ "$KEYED" = 1 ]; then
    echo "OK: -ignorestderr means the noise, and the value still came back"
else
    echo "FAIL: the keyed exec's value did not come back ($KEYED)"
fi
if [ "$ORDER3" = "routed starts|eager answered|routed done|" ]; then
    echo "OK: a redirect rides along — the pipeline parks with its own 2>"
else
    echo "FAIL: the routed order was «$ORDER3»"
fi
if [ "$ROUTED" = 1 ]; then
    echo "OK: a stream the line routed is no error, and the pipe spoke"
else
    echo "FAIL: the routed pipeline's value did not come back ($ROUTED)"
fi
check_invariants "$HERE/wm-coop.log"
