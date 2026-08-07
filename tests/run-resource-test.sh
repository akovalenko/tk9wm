#!/bin/sh
# Regression for RE-SOURCING THE LIBRARY ON A LIVE DESK — the
# development affordance: edit substrate.tcl or policy.tcl, press a
# key, and the running window manager is the new code, with every
# client, frame, grab and mode where it was.
#
# It cannot be reliable in general and is not meant to be (the owner,
# 2026-07-30): a proc that has gone away stays, a variable whose SHAPE
# changed keeps the old shape, and a half-finished edit is a half-
# finished desk. What it must not do is what it did — quietly take the
# desk apart. The bindings vanished, and `reload-config` did not bring
# them back.
#
# So the bar this test sets: after a re-source, the desk answers its
# chords, frames a new client, still owns its selection, and reloads
# its config. That is the whole contract.
. "$(dirname "$0")/common.sh"
start_xvfb
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
# The owner's own development binding, by hand — the long way, so that
# what is tested is the FILES being sourced again and not one proc's
# error handling. ALL THREE of them: main.tcl holds reload-config and
# load-config, and a re-source that skipped it once cost a live
# debugging session (a fix that lives there changed nothing). (`Reread` is that same pair, done properly: right
# order, caught errors. A second leg below presses it.)
wm-bind {<Super>s} {
    puts "WM: MARK re-sourcing"
    if {[catch {
        foreach f {substrate.tcl policy.tcl main.tcl} {
            source [file join $::tk9wm_library $f]
        }
    } err]} {
        puts "WM: MARK re-source FAILED: $err"
    } else {
        puts "WM: MARK re-sourced"
    }
}
wm-bind {<Super>a} Reread
wm-bind {<Super>d} {puts "WM: MARK the config's own chord"}
EOF
sleep 1

LOG="$HERE/wm-resource.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM
"$LINUX/whale" "$HERE/client.tcl" "старое" 300x200 "#fce94f" "" "" 60 &
CA=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.5; }

# --- before: both a default chord and the config's own answer
key alt+space
key Escape
key super+d
BEFORE_OPENS=$(grep -c 'winops open 0x' "$LOG")
BEFORE_CFG=$(grep -c "MARK the config's own chord" "$LOG")

# --- the re-source itself
key super+s
sleep 1.5

# --- after: the same two chords, a new client, and a reload
key alt+space
key Escape
key super+d
AFTER_OPENS=$(grep -c 'winops open 0x' "$LOG")
AFTER_CFG=$(grep -c "MARK the config's own chord" "$LOG")

"$LINUX/whale" "$HERE/client.tcl" "новое" 300x200+380+300 "#8ae234" "" "" 20 &
CB=$!
sleep 2
FRAMED=$(grep -c '^WM: managed ' "$LOG")

"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
sleep 1
key super+d
RELOAD_CFG=$(grep -c "MARK the config's own chord" "$LOG")

# --- and the same thing as the command the WM offers for it
key super+a
sleep 1.2
key super+d
COMMAND_CFG=$(grep -c "MARK the config's own chord" "$LOG")

ALIVE=0
kill -0 $WM 2>/dev/null && ALIVE=1
kill $WM $CA $CB 2>/dev/null

echo "--- marks and errors:"
grep -E 'MARK|WM: bye|standing down|handler error|key action error' "$LOG" | head -12

echo "--- verdict"
FAIL=0
if [ "$ALIVE" = 1 ]; then
    echo "OK: the window manager is still running"
else
    echo "FAIL: the WM died on (or after) the re-source"; FAIL=1
fi
if grep -q 'MARK re-sourced' "$LOG"; then
    echo "OK: both files sourced through without an error"
else
    echo "FAIL: the re-source itself did not complete:"; FAIL=1
    grep 'MARK re-source FAILED' "$LOG" | sed 's/^/    /'
fi
if [ "$AFTER_OPENS" -gt "$BEFORE_OPENS" ]; then
    echo "OK: an in-code chord still opens the menu ($BEFORE_OPENS -> $AFTER_OPENS)"
else
    echo "FAIL: Alt+Space is dead after the re-source (opens: $AFTER_OPENS)"
    FAIL=1
fi
if [ "$AFTER_CFG" -gt "$BEFORE_CFG" ]; then
    echo "OK: the CONFIG's own chord survived too ($BEFORE_CFG -> $AFTER_CFG)"
else
    echo "FAIL: the config's chord is gone after the re-source"; FAIL=1
fi
if [ "$FRAMED" = 2 ]; then
    echo "OK: a client mapped after the re-source was framed (2 managed)"
else
    echo "FAIL: $FRAMED clients managed in all — the new one was not framed"
    FAIL=1
fi
if [ "$RELOAD_CFG" -gt "$AFTER_CFG" ]; then
    echo "OK: reload-config still rebuilds the config's bindings"
else
    echo "FAIL: after a reload the config's chord no longer answers"; FAIL=1
fi
if grep -q 'WM: re-sourced (procs replaced' "$LOG" \
        && [ "$COMMAND_CFG" -gt "$RELOAD_CFG" ]; then
    echo "OK: the Reread command does it too, and the desk answers after"
else
    echo "FAIL: Reread did not go through (chord count $COMMAND_CFG)"; FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
