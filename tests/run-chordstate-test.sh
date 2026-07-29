#!/bin/sh
# Regression for what a chord IGNORES in a key event's state — the
# owner's question (2026-07-30): with the xkb group switched to
# Russian, does <Super>l still fire, and does it arrive as Cyrillic?
#
# Two halves, and only one of them was ever in danger.
#
# The KEYSYM was never at risk: handle-key asks the map for group 0
# level 0 by hand rather than trusting the event, so a chord is named
# by its Latin keysym whatever is being typed. That half is measured
# here too, by binding a chord to a key whose group 0 is Latin and
# firing it with the keycode.
#
# The STATE was. XKB reports the effective group in bits 13-14 of the
# CORE event state (XkbGroupForCoreState, X11/extensions/XKB.h:380) and
# the shim hands that state through untouched, while a chord's grab
# keeps working across a group change — XKB has a separate grab state
# with no group in it. So the press still arrived, gained 0x2000 on the
# way, and missed a table keyed on the bare modifier: the key was
# swallowed by our own grab and nothing ran.
#
# The battery is IN-PROCESS, feeding handle-key the states directly,
# and then a LIVE leg fires the chord through the server for real —
# through the group switch too, where the host allows one.
#
# The keymap arrives here; the GROUP still will not come into force,
# and the leg says so rather than passing on an assumption. What was
# measured on the way (2026-07-30), since two of the three explanations
# were wrong guesses of mine before they were checked:
#
#   - "Xvfb ignores XKB" — no. The extension is there and the server
#     runs the compiler on every setxkbmap, as its own stderr shows.
#   - the output directory — no. With XKM_OUTPUT_DIR writable, the
#     server's own invocation reproduced by hand compiles the us,ru map
#     to a 12940-byte .xkm and exits 0.
#   - the SERVER RESET — yes, this was it, and it was the owner's
#     diagnosis: an X server resets when its last client disconnects,
#     and a reset restores the default keymap. setxkbmap set the
#     layout, disconnected, and the reset undid it before anything
#     could look. Nothing failed and nothing complained. Hence
#     -noreset above, after which the layout sticks and keycode 46
#     really does carry Cyrillic_de in its second group.
#
# What remains is narrower and is about this server, not about us. The
# group can be LOCKED — `tkwmx::keyboard group 1` does it and a
# separate process reads back {1 1}, so the device state really
# changed — and an XTEST-injected key is unaffected by it either way:
# it still resolves in group 0 and its state still carries no group
# bits. (Pressing a bound ISO_Next_Group does not move the group at
# all, though the key, the compat interpretation and both groups are
# all present.) So no synthetic key can exercise the group path here,
# the live leg says so instead of pretending, and the in-process
# battery is what covers those states.
. "$(dirname "$0")/common.sh"
export DISPLAY=:52
rm -f /tmp/.X52-lock /tmp/.X11-unix/X52
# -noreset, and it is the whole reason this test can do its job. An X
# server RESETS when its last client disconnects, and a reset restores
# the default keymap — so setxkbmap would set the layout, disconnect,
# and the reset would undo it before anything else could look. Nothing
# fails and nothing complains; the map is simply always the default
# again. (The owner's diagnosis, 2026-07-30, after two wrong ones of
# mine — measured by holding an xterm open across the call, which makes
# the same setxkbmap stick.)
Xvfb :52 -screen 0 400x300x24 -noreset >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
trap 'kill $XVFB 2>/dev/null; rm -rf "$CONF"' EXIT
sleep 1.5

# A second group if this host will take one — the live leg below needs
# a group to switch to, and says so when there is none.
setxkbmap -layout us,ru -option grp:alt_shift_toggle 2>/dev/null
if xmodmap -pke | grep -qE "^keycode +46 = l L Cyrillic"; then
    TWOGROUP=yes
else
    TWOGROUP=no
fi
echo "--- keycode 46: $(xmodmap -pke | grep -E '^keycode +46 ' | sed 's/.*= //')"

cat > "$CONF/tk9wm.tcl" <<'EOF'
set ::fired 0
wm-bind {<Super>l} {incr ::fired; puts "CHORD FIRE"}

proc kchk {desc want got} {
    if {$got eq $want} {
        puts "CHORD PASS: $desc"
    } else {
        puts "CHORD FAIL: $desc (want $want, got $got)"
    }
    incr ::kchk_n
}
# One synthetic press of the bound chord, at a given state.
proc press {state} {
    set ::fired 0
    handle-key $state [x-keycode [x-keysym l]] 0
    return $::fired
}
after 1500 {
    set SUPER 64
    kchk "the bare chord fires"                1 [press $SUPER]
    kchk "...with CapsLock on"                 1 [press [expr {$SUPER | 2}]]
    kchk "...with NumLock on"                  1 [press [expr {$SUPER | 16}]]
    kchk "...in xkb group 1 (bit 13)"          1 [press [expr {$SUPER | 0x2000}]]
    kchk "...in xkb group 2 (bit 14)"          1 [press [expr {$SUPER | 0x4000}]]
    kchk "...in group 3 (both bits)"           1 [press [expr {$SUPER | 0x6000}]]
    kchk "...in a group with Caps and Num on"  1 \
        [press [expr {$SUPER | 0x2000 | 2 | 16}]]
    # ...and the bits that DO make a chord distinct still do
    kchk "a real extra modifier is not ignored: Shift" 0 [press [expr {$SUPER | 1}]]
    kchk "...nor Control"                      0 [press [expr {$SUPER | 4}]]
    kchk "the chord without its modifier does not fire" 0 [press 0]
    # The keysym half: the map is asked for group 0 level 0, so the
    # name a chord is keyed by is the Latin one whatever the group.
    kchk "the keysym a chord is matched on comes from group 0" \
        "l" [keysym-name [x-keysym-at [x-keycode [x-keysym l]] 0 0]]
    puts "CHORD DONE: $::kchk_n checks"
}
EOF

LOG="$HERE/wm-chordstate.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 4

# The LIVE leg: the same chord through the server, on the WM's own root
# grab (so nothing needs focus). First in group 0, which proves the
# plumbing of this leg wherever it runs; then after a group switch,
# which is the question.
fires_since_done() {
    sed -n '/^CHORD DONE/,$p' "$LOG" | grep -c '^CHORD FIRE'
}
xdotool key super+l; sleep 0.5
LIVE0=$(fires_since_done)

# A client to say which group is actually in force. The switch is NOT
# assumed: a toggle key can be bound, the compat map can carry the
# LockGroup interpretation, the map can have both groups — and the
# group can still not move (measured here, 2026-07-30). A leg that
# assumed it would pass whether or not the thing it names happened,
# which is worse than not having the leg.
GROUPMOVED=no
if [ "$TWOGROUP" = yes ]; then
    "$LINUX/whale" "$HERE/xkb-probe.tcl" > "$HERE/xkb-probe.log" 2>&1 &
    PROBE=$!
    sleep 2
    # Switched through the shim rather than by pressing a bound toggle:
    # it is the direct route (XkbLockGroup on the device) and it is
    # verifiable — the locker prints the group back.
    "$LINUX/whale" "$HERE/xkb-lock.tcl" "$ROOT" 1
    sleep 0.5
    xdotool key l; sleep 0.4          # ...and what does the group make of it?
    if grep -q 'keysym=Cyrillic' "$HERE/xkb-probe.log"; then
        GROUPMOVED=yes
        xdotool key super+l; sleep 0.5
        LIVE1=$(fires_since_done)
    fi
    kill $PROBE 2>/dev/null
fi
kill $WM 2>/dev/null
sleep 0.3

echo "--- battery:"
grep -E '^CHORD ' "$LOG" | sed 's/^/    /'

echo "--- verdict"
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
FAILS=$(grep -c '^CHORD FAIL' "$LOG")
DONE=$(sed -n 's/^CHORD DONE: \([0-9]*\) checks/\1/p' "$LOG")
if [ "$FAILS" = 0 ]; then
    echo "OK: no battery failures"
else
    echo "FAIL: $FAILS battery failures"
fi
if [ "$DONE" = 11 ]; then
    echo "OK: all 11 checks ran"
else
    echo "FAIL: the battery is missing or truncated (ran ${DONE:-0}, want 11)"
fi
if [ "$LIVE0" = 1 ]; then
    echo "OK: and the chord fires for real, through the server's grab"
else
    echo "FAIL: the live chord did not fire in group 0 ($LIVE0 fires)"
fi
if [ "$GROUPMOVED" = yes ]; then
    if [ "$LIVE1" = 2 ]; then
        echo "OK: ...and again with the group switched, which is the question"
    else
        echo "FAIL: the chord died on the group switch ($LIVE1 fires, want 2)"
    fi
elif [ "$TWOGROUP" = yes ]; then
    echo "SKIP: the second group is loaded and the device really is locked"
    echo "      into it (the shim reads it back), but an injected key still"
    echo "      resolves in group 0 and carries no group bits — see the"
    echo "      header. The in-process battery covers those states by hand."
else
    echo "SKIP: no second group on this host — a keymap could not be set."
    echo "      The in-process battery covers the same states by hand."
fi
check_invariants "$LOG"
