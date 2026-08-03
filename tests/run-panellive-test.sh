#!/bin/sh
# Regression for the live panel button: a button whose match sees a
# living window carries the persistent live state (indicator bar +
# face tint), two or more matches grow the arrow zone, the arrow
# drops the winlist filtered to the matches (MRU, pick focuses),
# and the judgement follows manage, unmanage and title changes —
# debounced. The body click stays the idempotent fire.
. "$(dirname "$0")/common.sh"
export DISPLAY=:92
rm -f /tmp/.X92-lock /tmp/.X11-unix/X92
Xvfb :92 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/panellive-config"
mkdir -p "$HERE/panellive-config"

# a client that starts matching and renames itself out of the match
cat > "$HERE/panellive-config/title-flip.tcl" <<'EOF'
package require Tk
wm title . жилец-C
wm geometry . 200x100
label .l -text флип -background #ad7fa8
pack .l -expand 1 -fill both
after 2500 { wm title . посторонний }
after 15000 exit
vwait ::forever
EOF

cat > "$HERE/panellive-config/tk9wm.tcl" <<'EOF'
action жилец {match {filter -title {жилец*}}}
action пусто {match {filter -title {нет-таких*}}}
panel-button жилец
panel-button пусто
proc lchk {desc want got} {
    if {$got eq $want} {
        puts "LIVE PASS: $desc"
    } else {
        puts "LIVE FAIL: $desc (want $want, got $got)"
    }
}
proc has-state {item state} {
    expr {$state in [[panel-tree default] item state get $item]}
}
proc by-title {pat} {
    foreach w [array names ::frameof] {
        if {[string match $pat [client-title $w]]} { return $w }
    }
    return 0
}
proc live-empty {} {
    lchk {empty desk: no live state} 0 [has-state 1 live]
    lchk {empty desk: the dud button is not live either} 0 [has-state 2 live]
    puts "LIVE BATTERY empty done"
}
proc sep-hidden {} {
    expr {[catch {[panel-tree default] item bbox 1 C0 eSep} bb] || $bb eq ""}
}
proc live-one {} {
    lchk {one match: live} 1 [has-state 1 live]
    lchk {one match: not multi} 0 [has-state 1 multi]
    lchk {one match: no separator drawn} 1 [sep-hidden]
    lchk {one match: the dud button stays dark} 0 [has-state 2 live]
    puts "LIVE BATTERY one done"
}
proc live-two {} {
    lchk {two matches: multi} 1 [has-state 1 multi]
    lchk {two matches: the separator is drawn} 0 [sep-hidden]
    # click the inner edge of the reserved strip — the whole zone is
    # the target, not the glyph
    lassign [[panel-tree default] item bbox 1] bx1 by1 bx2 by2
    # ON ITS OWN, as a real click is: a click arrives from a Tk binding,
    # while this battery is itself a chord's script — that is, already a
    # coroutine. The arrow WAITS for a row now, so calling it inline
    # would park the battery on an answer the battery was about to give.
    run-script "test click" [list panel-click default \
        [expr {$bx2 - 4}] [expr {($by1 + $by2) / 2}]]
    lchk {a zone-edge click opens the filtered list} 1 [winfo exists .winlist]
    lchk {the list holds exactly the matches} 2 [llength $::winlist_wins]
    lchk {MRU: the fresh window leads} [by-title жилец-B] \
        [lindex $::winlist_wins 0]
    .winlist.t selection clear
    .winlist.t selection add 2
    winlist-pick
    # THE PICK IS AN ANSWER NOW, not a deed: the list hands the window
    # back to whoever opened it (the arrow errand), and the substrate
    # wakes that waiter through the event loop — so the focus lands one
    # turn later, and a test that looks without turning sees the world
    # before the answer arrived.
    update; update idletasks
    lchk {picking the second entry focused the older one} \
        [by-title жилец-A] $::focused
    puts "LIVE BATTERY two done"
}
proc live-drop {} {
    lchk {after unmanage: still live} 1 [has-state 1 live]
    lchk {after unmanage: multi gone} 0 [has-state 1 multi]
    puts "LIVE BATTERY drop done"
}
proc live-multi2 {} {
    lchk {the flip client re-arms multi} 1 [has-state 1 multi]
    puts "LIVE BATTERY multi2 done"
}
proc live-single2 {} {
    lchk {the rename turned the matcher around: not multi} 0 \
        [has-state 1 multi]
    lchk {... but the standing match keeps live} 1 [has-state 1 live]
    puts "LIVE BATTERY single2 done"
}
# The owner's dream case (treesync): two buttons swap places -> the
# same two treectrl ITEMS swap places in the same tree — nothing is
# destroyed, the structure signature stood.
proc live-swap {} {
    set T [panel-tree default]
    set was $::panel_items(default)
    panel-buttons-own default
    panel-button пусто
    panel-button жилец
    update            ;# the idle rebuild — the items-only sync path
    lchk {swap: the tree widget survived} $T [panel-tree default]
    lchk {swap: both items survived by id} \
        [list [dict get $was жилец] [dict get $was пусто]] \
        [list [dict get $::panel_items(default) жилец] \
              [dict get $::panel_items(default) пусто]]
    lchk {swap: пусто leads the strip now} \
        [dict get $was пусто] [[panel-tree default] item firstchild root]
    puts "LIVE BATTERY swap done"
}
wm-bind {<Super>1} live-empty
wm-bind {<Super>2} live-one
wm-bind {<Super>3} live-two
wm-bind {<Super>4} live-drop
wm-bind {<Super>6} live-multi2
wm-bind {<Super>7} live-single2
wm-bind {<Super>8} live-swap
EOF

XDG_CONFIG_HOME="$HERE/panellive-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-panellive.log" 2>&1 &
WM=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.4; }

key super+1            # empty desk

"$LINUX/whale" "$HERE/client.tcl" жилец-A 240x120 "#729fcf" "" "" 60 &
CA=$!
sleep 1.5              # manage + the 200ms debounce
key super+2            # one match

"$LINUX/whale" "$HERE/client.tcl" жилец-B 240x120 "#8ae234" "" "" 60 &
CB=$!
sleep 1.5
key super+3            # two matches, the arrow drop, the pick

import -display :92 -window root "$HERE/panellive-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/panellive-test.png"

kill $CB 2>/dev/null   # unmanage drops multi
sleep 1.5
key super+4

"$LINUX/whale" "$HERE/panellive-config/title-flip.tcl" &
CC=$!
sleep 1.2              # managed as жилец-C, matches again
key super+6
sleep 2.5              # it renamed itself out of the match by now
key super+7
key super+8            # the swap: items move, nothing is destroyed

kill $WM $CA $CC 2>/dev/null

echo "--- battery lines:"
grep -E 'LIVE|arrow|winlist open' "$HERE/wm-panellive.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-panellive.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'LIVE FAIL' "$HERE/wm-panellive.log"; then
    echo "FAIL: battery failures present (above)"
else
    echo "OK: no battery failures"
fi
PASS=$(grep -c 'LIVE PASS' "$HERE/wm-panellive.log")
if [ "$PASS" = 20 ]; then
    echo "OK: all 20 checks passed"
else
    echo "FAIL: $PASS PASS lines, want 20"
fi
DONE=$(grep -c 'LIVE BATTERY .* done' "$HERE/wm-panellive.log")
if [ "$DONE" = 7 ]; then
    echo "OK: all seven batteries ran to completion"
else
    echo "FAIL: $DONE battery-done lines, want 7"
fi
if grep -q 'panel default: arrow on жилец' "$HERE/wm-panellive.log" \
   && grep -q 'action жилец: choose among 2 matches' "$HERE/wm-panellive.log"; then
    echo "OK: the arrow logged its two matches"
else
    echo "FAIL: no arrow log line"
fi
if grep -q 'handler error' "$HERE/wm-panellive.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-panellive.log"
fi
