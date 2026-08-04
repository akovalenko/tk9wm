#!/bin/sh
# Regression for Fire — run-or-raise as a word.
#
# The name form delegates to the declared action's own machinery; the
# inline form derives and fires without touching the registry: found
# is reached, nothing found is launched, `run` forces a launch past a
# standing match, `choose` opens the chooser over several matches.
# The terminal adapter round-trips whole — the first fire derives the
# match from the terminal's name and spawns, the second finds what
# the first spawned. The refusals are loud: a surface word (key) on
# an inline spec throws where it is written, an unmet needs says so
# instead of waiting in a registry it is not in.
. "$(dirname "$0")/common.sh"
export DISPLAY=:105
rm -f /tmp/.X105-lock /tmp/.X11-unix/X105
Xvfb :105 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

key() { xdotool key "$@"; sleep 1; }

CONF="$HERE/fire-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
action alpha {match {filter -title "фаерА*"}}
wm-bind {<Super>1} {Fire alpha}
wm-bind {<Super>2} {Fire {match {filter -title "фаерА*"}}}
wm-bind {<Super>3} {Fire {match {filter -title "нет-таких*"}
                          launch {puts "TEST: launched bare"}}}
wm-bind {<Super>4} {Fire {terminal {name fireterm} run {sleep 30}}}
wm-bind {<Super>5} {Fire {key {<Super>x} run {true}}}
wm-bind {<Super>6} {Fire {needs no-such-binary-xyzzy run {true}}}
wm-bind {<Super>7} {Fire {match {filter -title "фаерА*"}
                          launch {puts "TEST: forced run"}} run}
wm-bind {<Super>8} {Fire {match {filter -title "фаер?*"}} choose}
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$HERE/wm-fire.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "фаерА-окно" 200x100 "#fce94f" "" "" 90 \
    > "$HERE/fire-a.log" 2>&1 &
CA=$!
sleep 1
"$LINUX/whale" "$HERE/client.tcl" "фаерБ-окно" 220x120 "#8ae234" "" "" 90 \
    > "$HERE/fire-b.log" 2>&1 &
CB=$!
sleep 2

key super+1           # the name form: the action's own machinery
key super+2           # inline, found -> reached
key super+3           # inline, nothing matched -> launched
key super+7           # mode run forces a launch past a live match
key super+8           # choose over two matches
key 1                 # ...and reach the picked one
key super+5           # a surface word inline: refused where written
key super+6           # an unmet needs: refused out loud
key super+4           # the terminal adapter: derive, spawn
sleep 3
key super+4           # ...and find what it spawned
sleep 1

import -window root "$HERE/fire-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/fire-test.png"
kill $WM $CA $CB 2>/dev/null

echo "--- WM saw:"
grep -E 'WM: Fire|WM: action alpha|TEST:|cannot carry|winlist open' \
    "$HERE/wm-fire.log"

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$HERE/wm-fire.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
if grep -q 'soft failure\|handler error' "$HERE/wm-fire.log"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$HERE/wm-fire.log"; BAD=1
fi

if grep -q 'WM: action alpha: found 0x' "$HERE/wm-fire.log"; then
    echo "OK: Fire by name went through the declared action's machinery"
else
    echo "FAIL: Fire alpha never reached the action"; BAD=1
fi
FOUND=$(grep -c 'WM: Fire: found 0x' "$HERE/wm-fire.log")
if [ "$FOUND" = "3" ]; then
    echo "OK: the inline fires reached their windows (plain, chosen, terminal)"
else
    echo "FAIL: Fire: found $FOUND times, want 3"; BAD=1
fi
if grep -q 'TEST: launched bare' "$HERE/wm-fire.log"; then
    echo "OK: an inline spec with nothing matching launched"
else
    echo "FAIL: the bare launch never ran"; BAD=1
fi
if grep -q 'TEST: forced run' "$HERE/wm-fire.log"; then
    echo "OK: mode run forced a launch past a standing match"
else
    echo "FAIL: mode run did not launch"; BAD=1
fi
if grep -q 'WM: Fire: choose among 2 matches' "$HERE/wm-fire.log" \
        && grep -q 'winlist open (2 windows, chooser)' "$HERE/wm-fire.log"; then
    echo "OK: choose opened the chooser over both matches"
else
    echo "FAIL: the choose mode never asked"; BAD=1
fi
if grep -q 'Fire: an inline deed cannot carry key' "$HERE/wm-fire.log"; then
    echo "OK: a surface word on an inline spec is refused where written"
else
    echo "FAIL: the inline key was not refused"; BAD=1
fi
if grep -q 'WM: Fire: needs no-such-binary-xyzzy — not on this machine' \
        "$HERE/wm-fire.log"; then
    echo "OK: an unmet needs is refused out loud"
else
    echo "FAIL: the unmet needs said nothing"; BAD=1
fi
if grep -q 'WM: terminal: spawn .* -name fireterm' "$HERE/wm-fire.log"; then
    echo "OK: the terminal adapter wrapped the inline run, name and all"
else
    echo "FAIL: the terminal leg never spawned through the adapter"; BAD=1
fi

check_invariants "$HERE/wm-fire.log"
if grep -q 'WM: INVARIANT' "$HERE/wm-fire.log"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: Fire fires by name and by spec, and refuses what it must"
exit $BAD
