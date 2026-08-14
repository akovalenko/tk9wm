#!/bin/sh
# Regression: A WINDOW MAY CLAIM ITS LEADERS (keys-pass).
#
# The style key keys-pass names top chords the desk hands to the
# focused window instead of answering — a fullscreen RDP viewer whose
# remote desk has an Alt+Tab of its own gets it back, and the rest
# stay home. Under it sits the keyboard-sync grab: an idle press
# stands frozen until the dispatcher answers, and replay is the
# answer this suite watches for — a witness client that reports every
# key it receives can tell "the desk took it" from "the desk handed
# it over".
#
# Asserted, in order:
#  - a chord in the pass set, witness focused: the witness hears it,
#    the desk's own binding stays silent, the pass is said once in
#    the log — and held down, autorepeating through the WM, STILL
#    said once;
#  - the same chord with the other client focused: the desk answers
#    and no client hears a thing — the rule claims for ONE window;
#  - the bundle kind passes the family's CURRENT leaders (for chords
#    both of them, prefix and help), while the same leader still
#    opens the prefix for an unclaimed window; re-parameterize the
#    family and the pass follows its new prefix — resolution is at
#    the press, not a snapshot at the style merge;
#  - a crooked element (a bundle that is not on) complains ONCE and
#    the pairs after it still speak: fail-closed, not fail-dead;
#  - a sequence fired fast, no pass rule in sight: the second key
#    never leaks to a client, because the frozen queue holds it
#    until the sequence's own grab stands (the old race, closed by
#    construction — this is the suite saying so);
#  - a grab with NOTHING bound under it — the orphan — no longer
#    eats the letter: the frozen press is replayed, the letter
#    arrives, and the desk still answers afterwards.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/keyspass-config"
mkdir -p "$HERE/keyspass-config"
cat > "$HERE/keyspass-config/tk9wm.tcl" <<'EOF'
set-welcome off
wm-bind {<Alt>y} {puts "WM: the desk took Alt+y"} took-alty
wm-bind {<Super>g a} {puts "WM: the desk ran deep a"} deep-a
# nosuch is a deliberate crook: it must complain once, and must not
# cost the pairs after it their word
wm-style {filter -title passwit} \
    {keys-pass {bundle nosuch chord <Alt>y bundle chords}}
EOF

XDG_CONFIG_HOME="$HERE/keyspass-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-keyspass.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-keyspass.log" $WM

q() { printf '%s\n' "$1" > "$HERE/keyspass-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/keyspass-config/q.tcl"; }

"$LINUX/whale" "$HERE/client-press.tcl" passwit 240x120 "#729fcf" 60 \
    > "$HERE/keyspass-witness.log" 2>&1 &
WIT=$!
wait_client "$HERE/wm-keyspass.log" passwit
"$LINUX/whale" "$HERE/client-press.tcl" keyfree 240x120 "#fcaf3e" 60 \
    > "$HERE/keyspass-other.log" 2>&1 &
OTH=$!
wait_client "$HERE/wm-keyspass.log" keyfree

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-keyspass.log")
WID=$1; OID=$2
echo "--- actors: witness=$WID other=$OID"

# The verdict reads ::focused, so no scenario may fire until the WM
# believes the right window holds the focus — polled, not slept out.
focused_is() { [ "$(q 'format 0x%x $::focused')" = "$1" ]; }
focus() { xdotool search --name "$1" windowfocus
          wait_for 5 focused_is "$2" \
              || echo "note: the WM never took $1 ($2) for the focus"; }
key() { xdotool key "$@"; sleep 0.5; }

# ---- the chord kind: claimed by the witness ----
focus passwit "$WID"
key alt+y
PASSED1=$(grep -c 'key Alt+y -> passed to' "$HERE/wm-keyspass.log" || true)
TOOK1=$(grep -c 'the desk took Alt+y' "$HERE/wm-keyspass.log" || true)
HEARD1=$(grep -c 'key y state' "$HERE/keyspass-witness.log" || true)

# ...and held down: every autorepeat detours through the WM, the log
# says the pass once
xdotool keydown alt+y
sleep 1.2
xdotool keyup alt+y
sleep 0.5
PASSTORM=$(grep -c 'key Alt+y -> passed to' "$HERE/wm-keyspass.log" || true)
REPEATS=$(grep -c 'key y state' "$HERE/keyspass-witness.log" || true)

# ---- the same chord, the other window focused: the desk answers ----
focus keyfree "$OID"
key alt+y
TOOK2=$(grep -c 'the desk took Alt+y' "$HERE/wm-keyspass.log" || true)
LEAK2=$(grep -c 'key y state' "$HERE/keyspass-other.log" || true)

# ---- the bundle kind: both leaders of the chords family pass ----
focus passwit "$WID"
key super+t
key super+h
PASST=$(grep -c 'key Super+t -> passed to' "$HERE/wm-keyspass.log" || true)
PASSH=$(grep -c 'key Super+h -> passed to' "$HERE/wm-keyspass.log" || true)
HEARDT=$(grep -c 'key t state' "$HERE/keyspass-witness.log" || true)
HEARDH=$(grep -c 'key h state' "$HERE/keyspass-witness.log" || true)
GRIPES=$(grep -c 'keys-pass: bundle «nosuch» is not on' "$HERE/wm-keyspass.log" || true)

# ---- the same leader, unclaimed window: the prefix answers ----
# (z must stay UNBOUND under the prefix — run-key-test's note applies)
focus keyfree "$OID"
key super+t
key z
PREFIX=$(grep -c 'key Super+t -> prefix' "$HERE/wm-keyspass.log" || true)
ABORT=$(grep -c 'key sequence abort' "$HERE/wm-keyspass.log" || true)

# ---- late resolution: the family moves, the pass moves with it ----
q 'wm-keys chords -prefix {<Super>x} -help {<Super>slash}' >/dev/null
focus passwit "$WID"
key super+x
PASSX=$(grep -c 'key Super+x -> passed to' "$HERE/wm-keyspass.log" || true)
HEARDX=$(grep -c 'key x state' "$HERE/keyspass-witness.log" || true)

# ---- the sequence fired fast: the frozen queue holds the second key ----
focus keyfree "$OID"
xdotool key --delay 0 super+g a
sleep 0.7
DEEP=$(grep -c 'the desk ran deep a' "$HERE/wm-keyspass.log" || true)
LEAKSEQ=$(cat "$HERE/keyspass-witness.log" "$HERE/keyspass-other.log" \
    | grep -cE 'key [ga] state' || true)

# ---- the orphan: a grab with nothing under it gives the letter up ----
q 'x-grab-key [x-keycode m] 0 $::root sync; list orphan-armed' >/dev/null
focus passwit "$WID"
key m
ORPH=$(grep -c 'key m state' "$HERE/keyspass-witness.log" || true)
# ...and the desk still answers after replaying it
key alt+y
ALIVE=$(grep -c 'key Alt+y -> passed to' "$HERE/wm-keyspass.log" || true)

kill $WIT $OTH $WM 2>/dev/null
sleep 0.5

echo "--- pass/prefix lines:"
grep -E 'keys-pass|passed to|-> prefix|-> action|sequence abort' \
    "$HERE/wm-keyspass.log"
echo "--- verdict"
if [ "$PASSED1" = 1 ] && [ "$TOOK1" = 0 ] && [ "$HEARD1" = 1 ]; then
    echo "OK: the witness claimed Alt+y — heard it once, the desk's binding stayed silent"
else
    echo "FAIL: chord pass (passed=$PASSED1 took=$TOOK1 heard=$HEARD1)"
fi
if [ "$PASSTORM" = 1 ]; then
    echo "OK: held down, the pass was said once ($REPEATS presses reached the witness)"
else
    echo "FAIL: the autorepeat storm was logged $PASSTORM times, want 1"
fi
if [ "$TOOK2" = 1 ] && [ "$LEAK2" = 0 ]; then
    echo "OK: with the other window focused the desk took Alt+y and no client heard it"
else
    echo "FAIL: the control press (took=$TOOK2 leaked=$LEAK2)"
fi
if [ "$PASST" = 1 ] && [ "$PASSH" = 1 ] && [ "$HEARDT" -ge 1 ] && [ "$HEARDH" -ge 1 ]; then
    echo "OK: the bundle kind passed both of the family's leaders"
else
    echo "FAIL: bundle leaders (t=$PASST/$HEARDT h=$PASSH/$HEARDH)"
fi
if [ "$GRIPES" = 1 ]; then
    echo "OK: the crooked element complained once, and cost nothing after it"
else
    echo "FAIL: $GRIPES complaints about «nosuch», want exactly 1"
fi
if [ "$PREFIX" = 1 ] && [ "$ABORT" -ge 1 ]; then
    echo "OK: the same leader still opens the prefix for an unclaimed window"
else
    echo "FAIL: the prefix control (prefix=$PREFIX abort=$ABORT)"
fi
if [ "$PASSX" = 1 ] && [ "$HEARDX" -ge 1 ]; then
    echo "OK: the family moved to Super+x and the pass moved with it"
else
    echo "FAIL: late resolution (passed=$PASSX heard=$HEARDX)"
fi
if [ "$DEEP" = 1 ] && [ "$LEAKSEQ" = 0 ]; then
    echo "OK: the fast sequence ran and its second key never reached a client"
else
    echo "FAIL: the sequence race (action=$DEEP leaked=$LEAKSEQ)"
fi
if [ "$ORPH" -ge 1 ] && [ "$ALIVE" = 2 ]; then
    echo "OK: an orphaned grab replays its letter, and the desk stands after"
else
    echo "FAIL: the orphan (heard=$ORPH alive=$ALIVE)"
fi
check_invariants "$HERE/wm-keyspass.log"
