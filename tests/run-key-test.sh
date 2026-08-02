#!/bin/sh
# Regression for the key machinery and both popup menus. Clients A then
# B are managed (B holds the focus); then:
#  - Alt+Space opens the window OPS menu on the focused window; the
#    hotkey letter x fires maximize, twice = toggle there and back;
#  - the navigation keys run the menu: Ctrl+N/Ctrl+P unconditionally,
#    bare n/p and j/k when no hotkey claims the letter (none of winops'
#    x f c d r l does), Enter fires the selected action (raise);
#  - Alt+Tab with Alt held is the fvwm cycle: the list opens on the
#    Tab press, releasing Alt commits to the selection — a quick full
#    Alt+Tab toggles to the PREVIOUS window; a second Tab while Alt is
#    still down wraps the selection around (two windows: back to the
#    current one);
#  - the stumpwm-style sequence Super+t, w, m opens the ops menu for
#    the focused window through the prefix machinery, Esc closes;
# NOTE: the abort phase presses a key that must stay UNBOUND under
# the Super+t prefix. It used to press q, until Quit was bound to
# Super+t q and the 'abort' quietly became a real command — which
# ended the WM mid-test and failed the two checks after it as well.
# Bind a new default onto this key and the same will happen; pick
# another one here rather than weakening the check.
#
#  - Super+t followed by an unbound key aborts the sequence without
#    wedging anything (a final Alt+Space still answers).
. "$(dirname "$0")/common.sh"
export DISPLAY=:78
rm -f /tmp/.X78-lock /tmp/.X11-unix/X78
Xvfb :78 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-key.log" 2>&1 &
WM=$!
sleep 1.5

# the empty args skip resizeto/minsize; 60 s of lifetime outlives the
# whole key script (the stock 8 s died mid-test and read as a wedge)
"$LINUX/whale" "$HERE/client.tcl" "первое-окно" 240x120 "#8ae234" "" "" 60 &
CA=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "второе-окно" 240x120 "#fcaf3e" "" "" 60 &
CB=$!
sleep 1

key()     { xdotool key "$@"; sleep 0.5; }
keydown() { xdotool keydown "$@"; sleep 0.4; }
keyup()   { xdotool keyup "$@"; sleep 0.4; }

key alt+space   # winops on B
key x           # maximize B
key alt+space
key x           # ...and restore it
key alt+space   # navigation soak: nothing may fire
key ctrl+n      # -> fullscreen
key n           # -> close (bare n is free: no hotkey claims it)
key p           # -> fullscreen
key k           # -> maximize
key Escape
key alt+space
key j           # -> fullscreen
key j           # -> close
key j           # -> destroy
key j           # -> raise
key Return      # fires raise on B

keydown alt     # fvwm alt-tab: quick toggle to the previous window (A)
key Tab
keyup alt
keydown alt     # held cycle: second Tab wraps back around
key Tab
key Tab
keyup alt

key super+t     # the STATIC window list on the Super+t w w sequence...
key w
key w
import -display :78 -window root "$HERE/key-list.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/key-list.png"
key 2           # ...where a bare numbered hotkey picks entry 2 (B)
keydown alt     # cycle mode: the hotkey works WITH the modifier held
key Tab
key 2           # Alt+2 picks entry 2 (A) without waiting for release
keyup alt

key super+t     # prefix...
key w           # ...deeper...
key m           # ...winops on the focused window
import -display :78 -window root "$HERE/key-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/key-test.png"
key Escape
key super+t
key z           # unbound -> abort (see the note in the header)
key alt+space   # still alive after the abort
key Escape

# BUNDLES: the accord tree MOVES when its prefix does, the reflex
# bundle can be turned off whole, and the desk says where a thing
# lives instead of assuming it
qk() { printf '%s\n' "$1" > "$HERE/qk.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/qk.tcl"; }
BUNDLE=$(qk 'wm-keys accords -prefix {<Super>x} -help {<Super>slash}
             list moved [dict exists $::keymap [join [parse-chord {<Super>x}] ,]] \
                  oldgone [dict exists $::keymap [join [parse-chord {<Super>t}] ,]] \
                  help [chord-of key-help-open]')
BUNDLEOFF=$(qk 'wm-keys windows off
                list alttab [dict exists $::keymap [join [parse-chord {<Alt>Tab}] ,]] \
                     altf4 [dict exists $::keymap [join [parse-chord {<Alt>F4}] ,]]')
BUNDLEBACK=$(qk 'wm-keys windows
                 list alttab [dict exists $::keymap [join [parse-chord {<Alt>Tab}] ,]] \
                      close [chord-of Close]')

# A BINDING THAT HOLDS THE DESK says so afterwards — the plan's answer
# to «forbid a bare exec»: measure instead, because a slow send, a long
# after and a loop hang the desk exactly as well
qk 'set ::key_hold_warn 300
    wm-bind {<Super>F9} {after 700} slowpoke
    list armed' >/dev/null
key super+F9
sleep 1
HELD=$(qk 'set out none
    foreach p [problems] {
        if {[string match {*held the desk*} [dict get $p text]]} {
            set out [list [dict get $p what] held]
        }
    }
    set out')

kill $WM $CA $CB 2>/dev/null

# Actors by manage order (the 0.5 s spacing makes it deterministic).
set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-key.log")
AID=$1; BID=$2
echo "--- actors: A=$AID B=$BID"
echo "--- key/menu/focus lines:"
grep -E 'key |winops|winlist|focus ->' "$HERE/wm-key.log"

echo "--- held={$HELD}"
echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-key.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$AID" ] || [ -z "$BID" ]; then
    echo "FAIL: missing actor ids (A=$AID B=$BID)"
fi
OPENS=$(grep -c 'winops open 0x' "$HERE/wm-key.log")
if [ "$OPENS" = 6 ]; then
    echo "OK: winops opened 6 times"
else
    echo "FAIL: winops opened $OPENS times, want 6"
fi
ACTS=$(sed -n 's/^WM: winops 0x[0-9a-f]* //p' "$HERE/wm-key.log" | tr '\n' ' ')
if [ "$ACTS" = "Maximize Maximize Raise " ]; then
    echo "OK: hotkey x toggled maximize twice, nav+Enter fired raise"
else
    echo "FAIL: winops actions were «$ACTS», want «Maximize Maximize Raise »"
fi
CYCLES=$(grep -c 'winlist open (2 windows, cycle)' "$HERE/wm-key.log")
if [ "$CYCLES" = 3 ]; then
    echo "OK: a held Alt opened the list in cycle mode, three times"
else
    echo "FAIL: $CYCLES cycle opens, want 3"
fi
if grep -q 'winlist open (2 windows)$' "$HERE/wm-key.log"; then
    echo "OK: the Super+t w w sequence opened the STATIC list"
else
    echo "FAIL: no static winlist open in the log"
fi
PICKS=$(sed -n 's/^WM: winlist pick \(0x[0-9a-f]*\)$/\1/p' "$HERE/wm-key.log" | tr '\n' ' ')
if [ "$PICKS" = "$AID $AID $BID $AID " ]; then
    echo "OK: alt-tab toggle, wraparound, bare hotkey 2, Alt+2 in cycle (picks: $PICKS)"
else
    echo "FAIL: winlist picks were «$PICKS», want «$AID $AID $BID $AID »"
fi
if grep -q 'key Super+t -> prefix' "$HERE/wm-key.log" \
        && grep -q 'key w -> prefix' "$HERE/wm-key.log" \
        && grep -q 'key m -> action' "$HERE/wm-key.log"; then
    echo "OK: the Super+t w m sequence walked prefix, prefix, action"
else
    echo "FAIL: sequence steps missing from the log"
fi
if grep -q 'key sequence abort (z unbound)' "$HERE/wm-key.log"; then
    echo "OK: an unbound key aborted the sequence"
else
    echo "FAIL: no abort line for the unbound key"
fi
# The last Alt+Space must come AFTER the abort — proof the grab state
# survived it (the log is chronological).
if awk '/key sequence abort/ {a=1} a && /winops open/ {ok=1} END {exit !ok}' \
        "$HERE/wm-key.log"; then
    echo "OK: the machinery still answers after the abort"
else
    echo "FAIL: no winops open after the abort"
fi
check_invariants "$HERE/wm-key.log"

echo "--- bundles: {$BUNDLE} {$BUNDLEOFF} {$BUNDLEBACK}"
case "$BUNDLE" in
    "moved 1 oldgone 0 help Super+slash")
        echo "OK: the accord tree moved with its prefix, help key and all" ;;
    *) echo "FAIL: bundle move: $BUNDLE" ;;
esac
case "$BUNDLEOFF|$BUNDLEBACK" in
    "alttab 0 altf4 0|alttab 1 close Alt+F4")
        echo "OK: the reflex bundle goes off and comes back whole" ;;
    *) echo "FAIL: bundle off/on: $BUNDLEOFF | $BUNDLEBACK" ;;
esac

if [ "$HELD" = "{key Super+F9} held" ]; then
    echo "OK: a binding that held the desk says how long, afterwards"
else
    echo "FAIL: the hold measure: $HELD"
fi
