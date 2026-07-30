#!/bin/sh
# Regression for what a chord sequence SAYS about itself, and for the
# rule that a top chord is always live.
#
# Both come from the same report (the owner, 2026-07-30): a prefix
# takes the whole keyboard in silence, so a half-typed sequence is
# indistinguishable from a wedged desk — and the way one gets there is
# reaching for <Super>t after being distracted, when a <Super>t is
# already pending, which used to resolve to an undefined key and say
# nothing at all about that either.
#
# The config gives this display one extra bind — <Super>t <Super>t —
# to prove the restart is the GENERAL rule and not a special case for
# the prefix key: where the submap binds it, the submap wins.
. "$(dirname "$0")/common.sh"
export DISPLAY=:57
rm -f /tmp/.X57-lock /tmp/.X11-unix/X57
Xvfb :57 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
trap 'kill $XVFB 2>/dev/null; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-key-echo-place {left top}
wm-bind {<Super>t <Super>t} {puts "WM: the submap kept its own Super+t"}
# The DISPLAYED spelling, typed straight back in: this must land in the
# very same submap the in-code <Super>t defaults built.
wm-bind {Super+t Ctrl+j} {puts "WM: the shown spelling binds too"}
# A shifted symbol is spelled by the key it sits on: pressing it comes
# in as <Shift>slash on any layout, never as `question` (see the help
# key's comment in the substrate).
wm-bind {<Super>t <Shift>slash} {puts "WM: shift-slash, not question"}
EOF
sleep 1

LOG="$HERE/wm-keyecho.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" "окно" 300x200 "#fce94f" "" "" 120 &
CA=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.5; }
# The box, from OUTSIDE this process: its own log saying it drew
# something is not evidence that anything is on the screen.
echo_id() { xdotool search --onlyvisible --name '^tk9wm-key-echo$' 2>/dev/null | head -1; }
echo_at() {
    id=$(echo_id)
    [ -n "$id" ] || { echo "(no box)"; return; }
    xwininfo -id "$id" | awk '
        /Absolute upper-left X/ {x=$NF} /Absolute upper-left Y/ {y=$NF}
        END {print "+" x "+" y}'
}
# What the box last said, per the WM's own log — the text is ours to
# read there; that it is ON THE SCREEN is what echo_id answers.
last_echo() { sed -n 's/^WM: key echo ([a-z]*) «\(.*\)»$/\1/p' "$LOG" | tail -1; }

# --- 0. IT MUST NOT FLASH ANYWHERE FIRST. A box that maps before its
#        geometry lands appears at the toolkit's idea of a place and
#        jumps to ours a heartbeat later (the owner saw it in a corner,
#        2026-07-30). A screenshot cannot be relied on to catch
#        something that short — the SERVER's own event order can, and
#        xev is the witness: for one chord and one Escape there must be
#        no ConfigureNotify at all between the map and the unmap.
XEVLOG="$HERE/keyecho-xev.log"
stdbuf -oL xev -root -event substructure > "$XEVLOG" 2>&1 &
XEV=$!
sleep 0.5
key super+t
EID=$(echo_id)
key Escape
kill $XEV 2>/dev/null
FLASH=$(awk -v id="$(printf '0x%x,' "${EID:-0}")" '
    /^[A-Za-z]+ event,/ { type = $1 }
    index($0, "window " id) && type != "" {
        if (type == "MapNotify")     { up = 1; next }
        if (type == "UnmapNotify")   { up = 0; next }
        if (up && type == "ConfigureNotify") { n++ }
    }
    END { print n + 0 }' "$XEVLOG")
MAPS=$(awk -v id="$(printf '0x%x,' "${EID:-0}")" '
    /^[A-Za-z]+ event,/ { type = $1 }
    index($0, "window " id) && type == "MapNotify" { n++ }
    END { print n + 0 }' "$XEVLOG")

# --- 1. a prefix shows itself, and follows the typing
key super+t
E1=$(last_echo); ID1=$(echo_id); AT1=$(echo_at)
key w
E2=$(last_echo)
import -display :57 -window root "$HERE/keyecho-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/keyecho-test.png"

# --- 2. ...and goes away when the sequence resolves
key m                      # winops on the focused window
ID2=$(echo_id)
key Escape

# --- 3. an undefined key is not silence
key super+t
key z
E3=$(last_echo); ID3=$(echo_id)
sleep 1.2                  # KEY_ECHO_HOLD, and then it is gone
ID4=$(echo_id)

# --- 4. a top chord restarts the sequence from there (depth 2, where
#        nothing binds <Super>t), and the echo starts over with it
key super+t
key w
key super+t
E5=$(last_echo)
key w
key m                      # ...and the restarted sequence still walks
key Escape

# --- 5. where the SUBMAP binds it, the submap wins (depth 1)
key super+t
key super+t

# --- 5b. the shown spelling, and a shifted symbol by its own key
key super+t
key ctrl+j
key super+t
key question              # xdotool presses shift+slash for this

# --- 6. a top chord that is an ACTION is live from inside a sequence
key super+t
key alt+space
key Escape

# --- 6b. the help: what is under this prefix, on demand, and the
#         sequence still standing where it was when asked
key super+t
key w
key super+h
HELP=$(last_echo)
IDH=$(echo_id)
import -display :57 -window root "$HERE/keyecho-help.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/keyecho-help.png"
key m                     # ...and the prefix still walks on from there
key Escape

# --- 7. a DELAY is the Emacs reading: the box waits for hesitation,
#        and a sequence typed at speed never draws one. Reloaded in
#        place, which also says the knob survives a reload.
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-key-echo 900
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" :57 >/dev/null 2>&1
sleep 1
key super+t                # key() waits 0.5 s — less than the delay
ID5=$(echo_id)
sleep 0.7
ID6=$(echo_id)
key Escape

kill $WM $CA 2>/dev/null

echo "--- key/echo lines:"
grep -E 'key |echo' "$LOG"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ "$MAPS" = 1 ] && [ "$FLASH" = 0 ]; then
    echo "OK: the box mapped once, already in its place (no move after the map)"
else
    echo "FAIL: the box mapped $MAPS time(s) and moved $FLASH time(s) while up\
 — it flashed somewhere first (window ${EID:-none}, see $XEVLOG)"
fi
if [ "$E1" = "Super+t …" ] && [ "$E2" = "Super+t w …" ]; then
    echo "OK: the echo read «$E1» then «$E2»"
else
    echo "FAIL: the echo read «$E1» then «$E2», want «Super+t …» / «Super+t w …»"
fi
if [ -n "$ID1" ]; then
    echo "OK: the box was really on the screen (id $ID1 at $AT1)"
else
    echo "FAIL: no mapped tk9wm-key-echo window while the prefix was pending"
fi
if [ "$AT1" = "+0+0" ]; then
    echo "OK: set-key-echo-place {left top} put it in the corner ($AT1)"
else
    echo "FAIL: the box sits at $AT1, want +0+0 for {left top}"
fi
if [ -z "$ID2" ]; then
    echo "OK: the box left with the sequence it was about"
else
    echo "FAIL: the box outlived the sequence (id $ID2)"
fi
if [ "$E3" = "Super+t z is undefined" ] && [ -n "$ID3" ]; then
    echo "OK: the undefined key said so, on the screen («$E3»)"
else
    echo "FAIL: after the unbound key the echo read «$E3», box «$ID3»"
fi
if [ -z "$ID4" ]; then
    echo "OK: ...and the message stood for its second, not forever"
else
    echo "FAIL: the flash never went away (id $ID4)"
fi
if grep -q 'WM: key Super+t restarts the sequence' "$LOG"; then
    echo "OK: a top chord restarted the sequence"
else
    echo "FAIL: no restart line in the log"
fi
if [ "$E5" = "Super+t …" ]; then
    echo "OK: the echo started over with it («$E5», not «Super+t w Super+t»)"
else
    echo "FAIL: after the restart the echo read «$E5», want «Super+t …»"
fi
OPENS=$(grep -c 'winops open 0x' "$LOG")
if [ "$OPENS" = 4 ]; then
    echo "OK: winops opened 4 times (plain, after a restart, by Alt+Space from\
 inside a sequence, and after the help)"
else
    echo "FAIL: winops opened $OPENS times, want 4"
fi
if grep -q 'WM: the shown spelling binds too' "$LOG"; then
    echo "OK: «Super+t Ctrl+j» — the spelling the desk shows — bound, into the\
 same submap as the in-code defaults"
else
    echo "FAIL: the displayed spelling did not bind (or landed elsewhere)"
fi
if grep -q 'WM: shift-slash, not question' "$LOG"; then
    echo "OK: a shifted symbol answers to <Shift>slash, which is how it arrives"
else
    echo "FAIL: <Shift>slash never fired"
fi
case "$HELP" in
    "Super+t w …"*"m  →  winops"*"w  →  winlist"*)
        echo "OK: the help listed what is under Super+t w" ;;
    *)  echo "FAIL: the help read «$HELP»" ;;
esac
if [ -n "$IDH" ]; then
    echo "OK: ...on the screen, in the same box"
else
    echo "FAIL: the help never made it onto the screen"
fi
if grep -q 'WM: the submap kept its own Super+t' "$LOG"; then
    echo "OK: the submap's own <Super>t beat the restart"
else
    echo "FAIL: the submap's <Super>t never fired — the restart ate it"
fi
# The Alt+Space leg: an ACTION reached from inside a sequence. Its
# restart line must be followed by the action, with no abort between.
if awk '/key Alt\+space restarts the sequence/ {a=1; next}
        a && /key sequence abort/ {exit 1}
        a && /key Alt\+space -> action/ {ok=1} END {exit !ok}' "$LOG"; then
    echo "OK: a top-level ACTION fired from inside a sequence"
else
    echo "FAIL: Alt+Space from inside a sequence did not reach its action"
fi
if [ -z "$ID5" ] && [ -n "$ID6" ]; then
    echo "OK: with a delay set, the box waited for the hesitation"
else
    echo "FAIL: delayed echo — box at 0.5 s «$ID5», at 1.2 s «$ID6»;\
 want none then one"
fi
check_invariants "$LOG"
