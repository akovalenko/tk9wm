#!/bin/sh
# Regression for the pressed button and the taskbar toggle: the button
# whose window holds the focus carries the persistent focused state
# (the relief inverts, the face darkens), the judgement follows the
# focus — debounced with the rest — and under set-panel-toggle on a
# body press on that very button iconifies the window instead of
# reaching it; the next press brings it back. A press on a live but
# UNFOCUSED button stays the plain reach, toggle or no toggle.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/paneltoggle-config"
mkdir -p "$HERE/paneltoggle-config"

cat > "$HERE/paneltoggle-config/tk9wm.tcl" <<'EOF'
set-panel-toggle on
proc is-toggle-client {w} { expr {[client-title $w] eq "тумблер-клиент"} }
action тум {
    match is-toggle-client
    launch {exec __LINUX__/whale __HERE__/client.tcl тумблер-клиент 240x120 #729fcf {} {} 60 &}
}
panel-button тум
proc tchk {desc want got} {
    if {$got eq $want} {
        puts "TOGGLE PASS: $desc"
    } else {
        puts "TOGGLE FAIL: $desc (want $want, got $got)"
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
# ON ITS OWN, as a real click is (the panellive lesson): the battery
# runs as a chord's script — already a coroutine — and the click must
# arrive from the event loop the way a Tk binding delivers it.
proc press {} {
    lassign [[panel-tree default] item bbox 1] x1 y1 x2 y2
    run-script "test press" [list panel-click default \
        [expr {($x1 + $x2) / 2}] [expr {($y1 + $y2) / 2}]]
}
proc tgl-pressed {} {
    tchk {the focused window's button is pressed} 1 [has-state 1 focused]
    tchk {...and live, as ever} 1 [has-state 1 live]
    puts "TOGGLE BATTERY pressed done"
}
proc tgl-reach {} {
    tchk {focus elsewhere: the button is not pressed} 0 [has-state 1 focused]
    press               ;# unfocused button: the plain reach, no iconify
    puts "TOGGLE BATTERY reach done"
}
proc tgl-away {} {
    set w [by-title тумблер-клиент]
    tchk {the reach landed the focus on the client} $w $::focused
    tchk {...and the button is pressed again} 1 [has-state 1 focused]
    press               ;# focused button: this press puts it away
    puts "TOGGLE BATTERY away done"
}
proc tgl-gone {} {
    set w [by-title тумблер-клиент]
    tchk {the window is iconic} 1 [info exists ::iconic($w)]
    tchk {the focus left it} 0 [expr {$::focused == $w}]
    tchk {the button popped back out} 0 [has-state 1 focused]
    tchk {...but stays live: the window still is} 1 [has-state 1 live]
    press               ;# the way back: mru reaches the iconic window
    puts "TOGGLE BATTERY gone done"
}
proc tgl-back {} {
    set w [by-title тумблер-клиент]
    tchk {the window is back} 0 [info exists ::iconic($w)]
    tchk {...and holds the focus} $w $::focused
    tchk {...and its button is pressed} 1 [has-state 1 focused]
    puts "TOGGLE BATTERY back done"
}
wm-bind {<Super>1} tgl-pressed
wm-bind {<Super>2} tgl-reach
wm-bind {<Super>3} tgl-away
wm-bind {<Super>4} tgl-gone
wm-bind {<Super>5} tgl-back
EOF
sed -i "s|__LINUX__|$LINUX|; s|__HERE__|$HERE|" "$HERE/paneltoggle-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/paneltoggle-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-paneltoggle.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-paneltoggle.log" $WM

key() { xdotool key "$@"; sleep 0.5; }

"$LINUX/whale" "$HERE/client.tcl" тумблер-клиент 240x120 "#729fcf" "" "" 60 &
CA=$!
wait_client "$HERE/wm-paneltoggle.log" 'тумблер-клиент'
sleep 0.5              # the 200ms debounce
key super+1            # the fresh window's button is pressed in

"$LINUX/whale" "$HERE/client.tcl" "другое-окно" 240x120 "#fcaf3e" "" "" 60 &
CB=$!
wait_client "$HERE/wm-paneltoggle.log" 'другое-окно'
sleep 0.5              # the distractor holds the focus, judged by now
key super+2            # unfocused button: press reaches, no toggle
sleep 0.7              # the focus landed, the debounce ran
key super+3            # pressed button: press puts the window away
sleep 0.7
key super+4            # iconic, popped out — press brings it back
sleep 1.0              # deiconify invites the focus asynchronously
key super+5            # back, focused, pressed

import -display "$DISPLAY" -window root "$HERE/paneltoggle-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/paneltoggle-test.png"

kill $WM $CA $CB 2>/dev/null

echo "--- battery lines:"
grep -E 'TOGGLE|action тум' "$HERE/wm-paneltoggle.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-paneltoggle.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'TOGGLE FAIL' "$HERE/wm-paneltoggle.log"; then
    echo "FAIL: battery failures present (above)"
else
    echo "OK: no battery failures"
fi
PASS=$(grep -c 'TOGGLE PASS' "$HERE/wm-paneltoggle.log")
if [ "$PASS" = 12 ]; then
    echo "OK: all 12 checks passed"
else
    echo "FAIL: $PASS PASS lines, want 12"
fi
DONE=$(grep -c 'TOGGLE BATTERY .* done' "$HERE/wm-paneltoggle.log")
if [ "$DONE" = 5 ]; then
    echo "OK: all five batteries ran to completion"
else
    echo "FAIL: $DONE battery-done lines, want 5"
fi
if [ "$(grep -c 'action тум: focused already — iconifying' "$HERE/wm-paneltoggle.log")" = 1 ]; then
    echo "OK: exactly one press was the toggle"
else
    echo "FAIL: want exactly 1 iconifying line, got\
 $(grep -c 'focused already' "$HERE/wm-paneltoggle.log")"
fi
