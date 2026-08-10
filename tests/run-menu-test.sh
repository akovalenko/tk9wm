#!/bin/sh
# Regression for the config's own menus (wm-menu) and the list that
# answers (Choose).
#
# The static menu proves the row grammar whole: an action reference
# with an explicit mnemonic, a bare action name, a label+do pair — and
# the auto-numbering that steps over claimed keys (the do row must
# answer to 2, because 1 is the reference's own). A waiting action and
# an unknown name are skipped with a line apiece, so the menu opens
# with exactly three rows out of five declared.
#
# The dynamic menu's body counts its own openings out loud, which is
# the proof the rows are asked for AT OPEN TIME rather than once at
# declaration. Choose runs inside an ordinary binding — the coroutine
# run-script already gives it — and answers the picked row's value, or
# empty for an Escape.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1; }

# The desk: two reachable deeds, one waiting, and the three kinds of
# row — a reference with its own mnemonic, a bare name, a label+do
# pair. m1 is the static menu, m2 the dynamic one (its body counts its
# own openings out loud), and <Super>c parks a Choose in an ordinary
# binding.
CONF="$HERE/menu-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
action alpha {match {filter -title "менюА*"}}
action beta  {match {filter -title "менюБ*"}}
action ghost {needs no-such-binary-xyzzy run {no-such-binary-xyzzy}}
wm-menu m1 {
    key {<Super>m}
    items {
        {action alpha key 1}
        {label "сказать" do {puts "TEST: do fired"}}
        beta
        {label "инлайн" action {launch {puts "TEST: inline fired"}}}
        {action ghost}
        nosuch
    }
}
set ::m2_count 0
proc m2-items {} {
    incr ::m2_count
    puts "TEST: m2 built $::m2_count"
    list [list label "раз $::m2_count" do {puts "TEST: dyn one"}] \
         {label два do {puts "TEST: dyn two"} key d}
}
wm-menu m2 {key {<Super>t s} body {m2-items}}
wm-menu m3 {key {<Super>b} place {right bottom}
            items {{label угловой do {puts "TEST: m3 picked"}}}}
wm-bind {<Super>c} {puts "TEST: chose <[Choose {alpha {label бета value B key b}}]>"}
wm-bind {<Super>r} Reload
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-menu.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-menu.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "менюА-окно" 200x100 "#fce94f" "" "" 90 \
    > "$HERE/menu-a.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-menu.log" 'менюА-окно'
"$LINUX/whale" "$HERE/client.tcl" "менюБ-окно" 220x120 "#8ae234" "" "" 90 \
    > "$HERE/menu-b.log" 2>&1 &
CB=$!
wait_client "$HERE/wm-menu.log" 'менюБ-окно'

# ---- the static menu: hotkeys explicit, automatic, and skipped-over
key super+m
key 3                 # beta's automatic key (1 claimed, do-row took 2)
key super+m
key 2                 # the do row — proves the numbering stepped over 1
key super+m
key 1                 # the explicit mnemonic
key super+m
key 4                 # the inline spec, fired through Fire's door
key super+m
key Escape            # dismissal leaves nothing standing

# ---- the ends of the list, in every dialect
key super+m
key End               # the last row: инлайн
key Return
key super+m
key ctrl+e            # emacs's end...
key ctrl+a            # ...and its way back to the top: alpha
key Return
key super+m
key Next              # a page down is the bottom here
key Return
key super+m
key End
key Home              # ...and Home leads back up
key Return

# ---- the dynamic menu: the body answers at open time
key super+t
key s
key d                 # the explicit mnemonic of the second row
key super+t
key s
key 1                 # the first row's automatic key
# ---- a said place overrules the working-out
key super+b
key 1
# ---- Choose, inside a binding
key super+c
key b
key super+c
key Escape
# ---- a reload redeclares the menus from the config
key super+r
sleep 1
key super+m
key Escape
sleep 1

import -window root "$HERE/menu-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/menu-test.png"
kill $WM $CA $CB 2>/dev/null

echo "--- WM saw:"
grep -E 'WM: menu|TEST:|WM: action (alpha|beta|ghost)' "$HERE/wm-menu.log"

echo "--- verdict"
BAD=0
if grep -q 'BadAccess request=2' "$HERE/wm-menu.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
fi
if grep -q 'soft failure\|handler error' "$HERE/wm-menu.log"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$HERE/wm-menu.log"; BAD=1
fi

OPENS=$(grep -c 'WM: menu m1 open (4 items)' "$HERE/wm-menu.log")
if [ "$OPENS" = "10" ]; then
    echo "OK: the static menu opened 10 times, 4 rows of 6 declared each time"
else
    echo "FAIL: m1 opened with 4 rows $OPENS times, want 10"; BAD=1
fi
# the ends: End and PgDn each landed on инлайн, Ctrl+E/Ctrl+A and
# End-then-Home each came back to alpha — counted, so a dead key
# cannot hide behind the picks the hotkeys already made
INL=$(grep -c 'WM: menu m1 pick «инлайн»' "$HERE/wm-menu.log")
ALP=$(grep -c 'WM: menu m1 pick «alpha»' "$HERE/wm-menu.log")
if [ "$INL" = "3" ] && [ "$ALP" = "3" ]; then
    echo "OK: End, Ctrl+E/Ctrl+A, PgDn and Home all found their ends"
else
    echo "FAIL: end-navigation picks: инлайн=$INL (want 3) alpha=$ALP (want 3)"; BAD=1
fi
if grep -q 'WM: menu m1: «ghost» is waiting — not shown' "$HERE/wm-menu.log" \
        && grep -q 'WM: menu m1: «nosuch» is not a deed this desk knows' \
               "$HERE/wm-menu.log"; then
    echo "OK: the waiting and the unknown row each skipped with a line"
else
    echo "FAIL: the skip lines for ghost/nosuch are missing"; BAD=1
fi
if grep -q 'WM: menu m1 pick «beta»' "$HERE/wm-menu.log" \
        && grep -q 'WM: action beta: found 0x' "$HERE/wm-menu.log"; then
    echo "OK: the bare-name row answered to its automatic key and reached beta"
else
    echo "FAIL: beta was not picked by 3, or the fire found nothing"; BAD=1
fi
if grep -q 'TEST: do fired' "$HERE/wm-menu.log"; then
    echo "OK: the do row answered to 2 — the numbering stepped over the claimed 1"
else
    echo "FAIL: the do row did not fire on 2"; BAD=1
fi
if grep -q 'WM: menu m1 pick «alpha»' "$HERE/wm-menu.log" \
        && grep -q 'WM: action alpha: found 0x' "$HERE/wm-menu.log"; then
    echo "OK: the explicit mnemonic 1 reached alpha"
else
    echo "FAIL: alpha was not picked by its explicit 1"; BAD=1
fi
if grep -q 'TEST: inline fired' "$HERE/wm-menu.log"; then
    echo "OK: an inline action spec fired through Fire's door"
else
    echo "FAIL: the inline row never fired"; BAD=1
fi
PROBS=$(grep -c 'WM: PROBLEM menu m1: «nosuch»' "$HERE/wm-menu.log")
if [ "$PROBS" = "2" ]; then
    echo "OK: the unknown reference is a PROBLEM — once per declaration, re-judged by the reload"
else
    echo "FAIL: the nosuch problem was recorded $PROBS times, want 2"; BAD=1
fi

if grep -q 'TEST: m2 built 1' "$HERE/wm-menu.log" \
        && grep -q 'TEST: m2 built 2' "$HERE/wm-menu.log"; then
    echo "OK: the body was asked at each open — the rows are dynamic"
else
    echo "FAIL: the body did not run once per open"; BAD=1
fi
if grep -q 'TEST: dyn two' "$HERE/wm-menu.log" \
        && grep -q 'TEST: dyn one' "$HERE/wm-menu.log"; then
    echo "OK: the dynamic rows fired by mnemonic and by automatic key"
else
    echo "FAIL: the dynamic rows did not both fire"; BAD=1
fi

M3GEO=$(sed -n 's/.*WM: menu m3 open (1 items) \([0-9]*x[0-9]*+[0-9]*+[0-9]*\).*/\1/p' \
    "$HERE/wm-menu.log" | head -1)
M3W=${M3GEO%%x*}; rest=${M3GEO#*x}
M3H=${rest%%+*}; xy=${rest#*+}
M3X=${xy%%+*}; M3Y=${xy#*+}
if [ -n "$M3GEO" ] && [ $((M3X + M3W)) -eq 800 ] && [ $((M3Y + M3H)) -eq 600 ] \
        && grep -q 'TEST: m3 picked' "$HERE/wm-menu.log"; then
    echo "OK: place {right bottom} put the menu into the corner ($M3GEO)"
else
    echo "FAIL: m3 landed at «$M3GEO», want it flush with 800x600"; BAD=1
fi

if grep -q 'TEST: chose <B>' "$HERE/wm-menu.log"; then
    echo "OK: Choose answered the picked row's value"
else
    echo "FAIL: Choose did not answer B"; BAD=1
fi
if grep -q 'TEST: chose <>' "$HERE/wm-menu.log"; then
    echo "OK: a dismissed Choose answered the empty answer"
else
    echo "FAIL: the dismissed Choose never came back empty"; BAD=1
fi

check_invariants "$HERE/wm-menu.log"
if grep -q 'WM: INVARIANT' "$HERE/wm-menu.log"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the config's menus open, number, skip, refresh and answer"
exit $BAD
