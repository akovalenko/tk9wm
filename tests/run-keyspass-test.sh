#!/bin/sh
# Regression: A WINDOW MAY CLAIM ITS LEADERS (keys-pass) — and the
# claim LIFTS the grabs.
#
# The style key keys-pass names top chords the desk gives up while
# the window holds the focus. The first cut answered with replay,
# and the owner's RDP viewer showed why replay cannot be the whole
# answer: a passive grab's activation blips FocusOut(NotifyGrab) at
# the client, an RDP-class client drops its held modifiers on any
# FocusOut, and Alt+Tab landed remotely as a bare Tab (2026-08-15).
# So a claim now SUSPENDS the server grabs themselves — the chord
# arrives natively, and an xev witness can prove the world stayed
# still. The sync grab stays as the fallback for a missed front.
#
# Asserted, in order:
#  - focusing the claiming window suspends its leaders (chord kind
#    and both of the bundle's, prefix and help) and says so once;
#    the chord arrives at the witness natively — no desk action, no
#    fallback line, no gripe storm (the crooked element speaks once);
#  - focusing the other window resumes the grabs: the desk answers
#    the chord and opens the prefix, and nothing leaks to a client;
#  - re-parameterizing the bundle UNDER the claim moves the
#    suspension with the family: resolution is at the settling, not
#    a snapshot (wm-keys is a front of its own);
#  - an xev witness under a claim sees its chord with NO
#    FocusOut(NotifyGrab) around it — the RDP-shaped assertion, the
#    bug this mechanism exists to close;
#  - a rogue grab standing where the claim says none should — the
#    missed front made flesh — still does not eat the key: the
#    frozen press is replayed and logged as the fallback;
#  - an orphaned grab replays its letter (the finally), and a
#    sequence fired with no delay keeps its second key off every
#    client (the frozen queue) — the sync half, regression-held.
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
wm-style {filter -title {Event Tester}} {keys-pass {chord <Alt>y}}
EOF

XDG_CONFIG_HOME="$HERE/keyspass-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-keyspass.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-keyspass.log" $WM

q() { printf '%s\n' "$1" > "$HERE/keyspass-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/keyspass-config/q.tcl"; }

"$LINUX/whale" "$HERE/client-press.tcl" passwit 240x120 "#729fcf" 90 \
    > "$HERE/keyspass-witness.log" 2>&1 &
WIT=$!
wait_client "$HERE/wm-keyspass.log" passwit
"$LINUX/whale" "$HERE/client-press.tcl" keyfree 240x120 "#fcaf3e" 90 \
    > "$HERE/keyspass-other.log" 2>&1 &
OTH=$!
wait_client "$HERE/wm-keyspass.log" keyfree

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-keyspass.log")
WID=$1; OID=$2
echo "--- actors: witness=$WID other=$OID"

# The claim settles off ::focused, so no scenario may fire until the
# WM believes the right window holds the focus — polled, not slept.
focused_is() { [ "$(q 'format 0x%x $::focused')" = "$1" ]; }
focus() { xdotool search --name "$1" windowfocus
          wait_for 5 focused_is "$2" \
              || echo "note: the WM never took $1 ($2) for the focus"; }
key() { xdotool key "$@"; sleep 0.5; }
saidc() { grep -c "$1" "$HERE/wm-keyspass.log" || true; }

# ---- the claim suspends: chord kind and both bundle leaders ----
focus passwit "$WID"
wait_for 5 grep -q 'grabs suspended' "$HERE/wm-keyspass.log"
SUSP1=$(saidc 'claims Alt+y, Super+t, Super+h — grabs suspended')
key alt+y
key super+t
key super+h
TOOK1=$(saidc 'the desk took Alt+y')
HEARDY=$(grep -c 'key y state' "$HERE/keyspass-witness.log" || true)
HEARDT=$(grep -c 'key t state' "$HERE/keyspass-witness.log" || true)
HEARDH=$(grep -c 'key h state' "$HERE/keyspass-witness.log" || true)
PREFIX1=$(saidc 'key Super+t -> prefix')
GRIPES=$(saidc 'keys-pass: bundle «nosuch» is not on')

# ---- the other window: grabs resumed, the desk answers again ----
focus keyfree "$OID"
wait_for 5 grep -q 'grabs resumed' "$HERE/wm-keyspass.log"
RESUMED=$(saidc 'grabs resumed (3)')
key alt+y
TOOK2=$(saidc 'the desk took Alt+y')
LEAK2=$(grep -c 'key y state' "$HERE/keyspass-other.log" || true)
# (z must stay UNBOUND under the prefix — run-key-test's note applies)
key super+t
key z
PREFIX2=$(saidc 'key Super+t -> prefix')
ABORT=$(saidc 'key sequence abort')

# ---- late resolution: the family moves UNDER the claim ----
focus passwit "$WID"
q 'wm-keys chords -prefix {<Super>x} -help {<Super>slash}' >/dev/null
sleep 0.5
SUSPX=$(saidc 'claims Alt+y, Super+x, Super+slash — grabs suspended')
key super+x
HEARDX=$(grep -c 'key x state' "$HERE/keyspass-witness.log" || true)
PREFIXX=$(saidc 'key Super+x -> prefix')

# ---- the xev witness: the chord arrives and the world stays still ----
xev > "$HERE/keyspass-xev.log" 2>&1 &
XEV=$!
wait_client "$HERE/wm-keyspass.log" 'Event Tester'
set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-keyspass.log")
XID=$3
focus 'Event Tester' "$XID"
sleep 0.5
key alt+y
BLIPS=$(grep -c 'NotifyGrab' "$HERE/keyspass-xev.log" || true)
XEVGOT=$(grep -c 'keysym 0x79, y' "$HERE/keyspass-xev.log" || true)
kill $XEV 2>/dev/null

# ---- the fallback: a rogue grab where the claim says none ----
# The q hands its keycode back and the verdict wants it nonzero — a
# grab that silently failed to arm would leave this phase measuring
# native delivery and calling it a fallback (the first cut of this
# suite did exactly that, x-keycode wanting a numeric keysym).
focus passwit "$WID"
ROGUE=$(q 'set kc [x-keycode [x-keysym y]]
           x-grab-key $kc 8 $::root sync; x-sync 0; list kc $kc')
key alt+y
FALLBACK=$(saidc 'key Alt+y -> passed to.*(keys-pass fallback)')
HEARDY2=$(grep -c 'key y state' "$HERE/keyspass-witness.log" || true)

# ---- the sync half, still standing: orphan and the frozen queue ----
ORPHAN=$(q 'set kc [x-keycode [x-keysym m]]
            x-grab-key $kc 0 $::root sync; x-sync 0; list kc $kc')
key m
ORPH=$(grep -c 'key m state' "$HERE/keyspass-witness.log" || true)
focus keyfree "$OID"
xdotool key --delay 0 super+g a
sleep 0.7
DEEP=$(saidc 'the desk ran deep a')
LEAKSEQ=$(cat "$HERE/keyspass-witness.log" "$HERE/keyspass-other.log" \
    | grep -cE 'key [ga] state' || true)

kill $WIT $OTH $WM 2>/dev/null
sleep 0.5

echo "--- claim/pass lines:"
grep -E 'keys-pass|passed to|-> prefix|-> action|sequence abort' \
    "$HERE/wm-keyspass.log"
echo "--- verdict"
# SUSP1 is >=1, not ==1: the witness legitimately claims twice — once
# when it maps and takes the focus, once when xdotool hands the focus
# back after the second client stole it.
if [ "$SUSP1" -ge 1 ] && [ "$HEARDY" = 1 ] && [ "$HEARDT" -ge 1 ] \
        && [ "$HEARDH" -ge 1 ] && [ "$TOOK1" = 0 ] && [ "$PREFIX1" = 0 ]; then
    echo "OK: the claim lifted all three leaders — the witness heard them, the desk stayed out"
else
    echo "FAIL: suspension (said=$SUSP1 y=$HEARDY t=$HEARDT h=$HEARDH took=$TOOK1 prefix=$PREFIX1)"
fi
if [ "$GRIPES" = 1 ]; then
    echo "OK: the crooked element complained once, and cost nothing after it"
else
    echo "FAIL: $GRIPES complaints about «nosuch», want exactly 1"
fi
if [ "$RESUMED" -ge 1 ] && [ "$TOOK2" = 1 ] && [ "$LEAK2" = 0 ] \
        && [ "$PREFIX2" = 1 ] && [ "$ABORT" -ge 1 ]; then
    echo "OK: with the other window focused the grabs resumed — desk action and prefix both answer"
else
    echo "FAIL: resume (resumed=$RESUMED took=$TOOK2 leak=$LEAK2 prefix=$PREFIX2 abort=$ABORT)"
fi
if [ "$SUSPX" = 1 ] && [ "$HEARDX" -ge 1 ] && [ "$PREFIXX" = 0 ]; then
    echo "OK: the family moved to Super+x under the claim, and the suspension moved with it"
else
    echo "FAIL: late resolution (said=$SUSPX heard=$HEARDX prefix=$PREFIXX)"
fi
if [ "$BLIPS" = 0 ] && [ "$XEVGOT" -ge 1 ]; then
    echo "OK: the claimed chord reached xev with no grab blip around it (the RDP shape)"
else
    echo "FAIL: the xev witness (blips=$BLIPS got=$XEVGOT)"
fi
case "$ROGUE" in
    "kc 0"|"") echo "FAIL: the rogue grab never armed ($ROGUE)" ;;
esac
if [ "$FALLBACK" = 1 ] && [ "$HEARDY2" = 2 ]; then
    echo "OK: a rogue grab under the claim was replayed and named the fallback it is"
else
    echo "FAIL: the fallback (line=$FALLBACK heard=$HEARDY2 rogue=$ROGUE)"
fi
case "$ORPHAN" in
    "kc 0"|"") echo "FAIL: the orphan grab never armed ($ORPHAN)" ;;
esac
if [ "$ORPH" -ge 1 ]; then
    echo "OK: an orphaned grab replays its letter"
else
    echo "FAIL: the orphan (heard=$ORPH orphan=$ORPHAN)"
fi
if [ "$DEEP" = 1 ] && [ "$LEAKSEQ" = 0 ]; then
    echo "OK: the fast sequence ran and its second key never reached a client"
else
    echo "FAIL: the sequence race (action=$DEEP leaked=$LEAKSEQ)"
fi
check_invariants "$HERE/wm-keyspass.log"
