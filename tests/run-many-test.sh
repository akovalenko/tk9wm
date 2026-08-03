#!/bin/sh
# Regression for `many` — what happens when a deed has SEVERAL windows.
#
# The knob governs the CHORD and nothing else: a panel button already
# wears both answers on its face (main area = most recent, arrow =
# choose), so a press of the body stays MRU however the deed is
# declared. Where a chord's chooser opens is the keyboard's own
# question — off the button when the deed is shown on a panel, in the
# middle of the screen when it has no face anywhere — and the list ends
# in the deed's «run another» row exactly when there is something to
# run.
#
# Every battery both OPENS and answers its own list, because an open
# popup holds the keyboard: a second chord would go to the list, not to
# the desk. The opening is `run-script [list action-fire ...]`, which is
# the binding's own payload word for word, in a coroutine of its own —
# a battery that fired inline would park on the answer it was about to
# give.
. "$(dirname "$0")/common.sh"
export DISPLAY=:95
rm -f /tmp/.X95-lock /tmp/.X11-unix/X95
Xvfb :95 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/many-config"
mkdir -p "$HERE/many-config"

cat > "$HERE/many-config/tk9wm.tcl" <<'EOF'
# Four deeds over the SAME two windows, differing only in the two
# things under test: whether the chord chooses, and whether the deed
# has a face on a panel.
action альфа {match {filter -title {клиент*}} many choose
              run {sh -c {sleep 30}}}
action бета  {match {filter -title {клиент*}} many choose
              run {sh -c {sleep 30}}}
action гамма {match {filter -title {клиент*}} many choose}
action мру   {match {filter -title {клиент*}} many mru
              run {sh -c {sleep 30}}}
panel-button альфа
panel-button мру

proc mchk {desc want got} {
    if {$got eq $want} {
        puts "MANY PASS: $desc"
    } else {
        puts "MANY FAIL: $desc (want $want, got $got)"
    }
}
proc by-title {pat} {
    foreach w [array names ::frameof] {
        if {[string match $pat [client-title $w]]} { return $w }
    }
    return 0
}
proc more-label {} {
    set last [.winlist.t item lastchild root]
    if {[catch {.winlist.t item element cget $last C0 eMore -text} t]} { return "" }
    return $t
}
proc centred-x {} {
    lassign [screen-size] sw sh
    expr {($sw - [winfo width .winlist]) / 2}
}
proc btn-item {aname} { dict get $::panel_items(default) $aname }
# The chord's payload, word for word — in its own coroutine, so the
# battery goes on running while the deed waits for an answer.
proc fire-aside {name} { run-script "test chord" [list action-fire $name] }
proc click-btn {aname where} {
    lassign [[panel-tree default] item bbox [btn-item $aname]] bx1 by1 bx2 by2
    set x [expr {$where eq "arrow" ? $bx2 - 4 : $bx1 + 3}]
    run-script "test click" \
        [list panel-click default $x [expr {($by1 + $by2) / 2}]]
}

# --- 1. a shown deed's chord: anchored, offers the row, and the row runs
proc many-anchored {} {
    fire-aside альфа
    mchk {a choose chord opened a list} 1 [winfo exists .winlist]
    mchk {the windows are the deed's two} 2 [llength $::winlist_wins]
    mchk {and one row more than windows} 3 [llength $::winlist_rows]
    mchk {the extra row answers «more»} more [lindex $::winlist_rows end]
    mchk {...and says what it will do} {Run another альфа} [more-label]
    mchk {a chooser starts on the most recent} 1 \
        [lindex [.winlist.t selection get] 0]
    mchk {anchored at its own button} [winfo rootx [panel-tree default]] \
        [winfo x .winlist]
    mchk {and above the strip, not under it} 1 \
        [expr {[winfo y .winlist] + [winfo height .winlist]
               <= [winfo y [panel-window default]]}]
    .winlist.t selection clear
    .winlist.t selection add [llength $::winlist_rows]
    winlist-pick
    update; update idletasks     ;# the answer wakes its waiter a turn later
    mchk {picking «run another» closes the list} 0 [winfo exists .winlist]
    puts "MANY BATTERY anchored done"
}
# --- 2. a deed NOBODY shows: centred, and it offers the row too
proc many-centred {} {
    fire-aside бета
    mchk {an unshown deed still opens a list} 1 [winfo exists .winlist]
    mchk {centred, having no button to hang off} [centred-x] [winfo x .winlist]
    mchk {it offers the row too} {Run another бета} [more-label]
    winlist-cancel
    update; update idletasks
    puts "MANY BATTERY centred done"
}
# --- 3. a deed with nothing to launch offers no row
proc many-norun {} {
    fire-aside гамма
    mchk {the list opened} 1 [winfo exists .winlist]
    mchk {rows are windows only} [llength $::winlist_wins] \
        [llength $::winlist_rows]
    mchk {no «run another» on a deed that cannot} {} [more-label]
    winlist-cancel
    update; update idletasks
    puts "MANY BATTERY norun done"
}
# --- 4. `many mru` is the old behaviour, unasked
proc many-mru {} {
    focus-to [by-title клиент-A]
    update
    fire-aside мру
    update; update idletasks
    mchk {no list for an mru deed} 0 [winfo exists .winlist]
    mchk {the most recent window got it} [by-title клиент-A] $::focused
    puts "MANY BATTERY mru done"
}
# --- 5. THE OWNER'S RULE: the button's body ignores `many`
proc many-body {} {
    focus-to [by-title клиент-B]
    update
    click-btn альфа body
    update; update idletasks
    mchk {a body press asks nothing, however the deed is declared} 0 \
        [winfo exists .winlist]
    mchk {it reached the most recent window} [by-title клиент-B] $::focused
    puts "MANY BATTERY body done"
}
# --- 6. ...and the arrow chooses, however the deed is declared
proc many-arrow {} {
    click-btn мру arrow
    mchk {the arrow of an MRU deed still opens the list} 1 \
        [winfo exists .winlist]
    mchk {and it is the deed's own filtered one} 2 [llength $::winlist_wins]
    winlist-cancel
    update; update idletasks
    puts "MANY BATTERY arrow done"
}
wm-bind {<Super>1} many-anchored
wm-bind {<Super>2} many-centred
wm-bind {<Super>3} many-norun
wm-bind {<Super>4} many-mru
wm-bind {<Super>5} many-body
wm-bind {<Super>6} many-arrow
EOF

XDG_CONFIG_HOME="$HERE/many-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-many.log" 2>&1 &
WM=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.5; }

"$LINUX/whale" "$HERE/client.tcl" клиент-A 240x120 "#729fcf" "" "" 90 &
CA=$!
sleep 1.2
"$LINUX/whale" "$HERE/client.tcl" клиент-B 240x120 "#8ae234" "" "" 90 &
CB=$!
sleep 1.5              # both managed, past the 200ms match debounce

key super+1            # shown deed: anchored chooser + «run another»
key super+2            # unshown deed: centred chooser
key super+3            # nothing to launch: no extra row
key super+4            # many mru: straight to the most recent
key super+5            # the button's body, on a `choose` deed
key super+6            # the arrow, on an `mru` deed

import -display :95 -window root "$HERE/many-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/many-test.png"

kill $WM $CA $CB 2>/dev/null

echo "--- battery lines:"
grep -E 'MANY|winlist open|action .*: (choose|launch)' "$HERE/wm-many.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-many.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'MANY FAIL' "$HERE/wm-many.log"; then
    echo "FAIL: battery failures present (above)"
else
    echo "OK: no battery failures"
fi
PASS=$(grep -c 'MANY PASS' "$HERE/wm-many.log")
if [ "$PASS" = 21 ]; then
    echo "OK: all 21 checks passed"
else
    echo "FAIL: $PASS PASS lines, want 21"
fi
DONE=$(grep -c 'MANY BATTERY .* done' "$HERE/wm-many.log")
if [ "$DONE" = 6 ]; then
    echo "OK: all six batteries ran to completion"
else
    echo "FAIL: $DONE battery-done lines, want 6"
fi
# The row is not decoration: picking it must actually start the deed.
if grep -q 'action альфа: launch' "$HERE/wm-many.log"; then
    echo "OK: the «run another» row launched the deed"
else
    echo "FAIL: the extra row started nothing"
fi
# Four choosers opened, and not one of them by a deed declared mru
# through the path that is supposed to ignore the knob.
if [ "$(grep -c 'choose among 2 matches' "$HERE/wm-many.log")" = 4 ]; then
    echo "OK: four choosers, one per asking gesture"
else
    echo "FAIL: choosers unaccounted for:\
 $(grep -c 'choose among' "$HERE/wm-many.log")"
fi
if grep -q 'handler error' "$HERE/wm-many.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-many.log"
fi
check_invariants "$HERE/wm-many.log"
