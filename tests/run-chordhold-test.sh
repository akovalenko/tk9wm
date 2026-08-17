#!/bin/sh
# Regression for HOLDING THE MODIFIER THROUGH A CHORD — «someone might
# like <Super>t<Super>w<Super>w without letting go» (the owner,
# 2026-08-02). One bind, both forms: the same declaration answers the
# release-and-press hand and the never-let-go hand alike, and nothing
# is declared twice.
#
# What is measured:
#
#  - with the knob OFF, only the written form answers — the held one
#    falls through as an unbound key, which is what it always did;
#  - with it ON, both forms fire the SAME binding;
#  - an exact chord still wins where one is written: a submap that
#    binds <Super>w beside a bare w keeps both, and the hold only ever
#    fills a gap;
#  - and the desk says what the knob COSTS — a top chord whose letter
#    a prefix also binds stops being reachable inside that prefix, and
#    that is named out loud rather than left as advice;
#  - what the action is TOLD about its chord (key_invoke_mods and
#    key_invoke_sym) is the PHYSICAL press: the held form of a
#    bare-written key reports the modifier it actually wore.
. "$(dirname "$0")/common.sh"
start_xvfb 800x500x24
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT

LOG="$HERE/wm-chordhold.log"
OUT="$CONF/fired"
cat > "$CONF/tk9wm.tcl" <<EOF
set-welcome off
set-chord-hold off
proc fired {what} {
    set ch [open "$OUT" a]
    puts \$ch "\$what \$::key_invoke_mods \$::key_invoke_sym"
    close \$ch
}
wm-bind {<Super>t z} {fired plain} "the plain inner key"
wm-bind {<Super>t <Super>y} {fired exact} "an inner key written WITH the modifier"
# ...and the letter of a top chord, under the same prefix: this is the
# collision the knob has to own up to.
wm-bind {<Super>t h} {fired collide} "the letter the help chord uses"
EOF
sleep 1
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 2

key() { xdotool key "$@"; sleep 0.6; }
fired() { tr '\n' ' ' < "$OUT" 2>/dev/null; }
q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1; }

# --- knob OFF: the written form answers, the held one does not
key super+t; key z
OFFPLAIN=$(fired)
: > "$OUT"
key super+t; key super+z
key Escape
OFFHELD=$(fired)
: > "$OUT"

q 'set-chord-hold on' >/dev/null
sleep 0.5
# --- knob ON: both forms, same binding
key super+t; key z
ONPLAIN=$(fired)
: > "$OUT"
key super+t; key super+z
ONHELD=$(fired)
: > "$OUT"
# --- an exactly-written inner chord still wins
key super+t; key super+y
ONEXACT=$(fired)
: > "$OUT"
SHADOW=$(grep -c 'with chord-hold on' "$LOG")
kill $WM 2>/dev/null

echo "--- off: plain «$OFFPLAIN» held «$OFFHELD»"
echo "--- on:  plain «$ONPLAIN» held «$ONHELD» exact «$ONEXACT»"
echo "--- shadow warnings in the log: $SHADOW"
grep 'with chord-hold on' "$LOG" | head -3

echo "--- verdict"
FAIL=0
want() {
    if [ "$2" = "$3" ]; then
        echo "OK: $1"
    else
        echo "FAIL: $1 — got «$2», wanted «$3»"; FAIL=1
    fi
}
want "off: the written form answers, told a bare press" \
    "$OFFPLAIN" "plain 0 z "
want "off: ...and the held one does not"        "$OFFHELD"  ""
want "on: the written form still answers, still a bare press" \
    "$ONPLAIN"  "plain 0 z "
want "on: ...the held one too, SAME binding, told the modifier it wore" \
    "$ONHELD" "plain 64 z "
want "on: an inner chord written with its modifier keeps it" \
    "$ONEXACT" "exact 64 y "
if [ "$SHADOW" -ge 1 ]; then
    echo "OK: the desk names what the knob costs, rather than advising"
else
    echo "FAIL: nothing said about the shadowed top chord"; FAIL=1
fi
if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors:"; grep 'handler error' "$LOG"; FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
