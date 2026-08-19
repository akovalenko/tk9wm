#!/bin/sh
# Regression for the refocus pick (WM_TRANSIENT_FOR + focus history).
# Scenario: leader A, then C, then B receive focus in turn; A pops a
# transient dialog D (focused). Closing D must refocus A — the dialog's
# LEADER — and not B, the most recently focused bystander (the smsrc
# observation: an app does not refocus its main window itself, that is
# the WM's job). Then A exits, and the focus history must hand focus to
# B (most recent living window), not an arbitrary managed one.
#
# Phase B: a whole APPLICATION leaves at once — four windows in one
# burst. The pick made as the first one goes names a sibling already
# dead on the server, so the aim is refused; the keyboard must still end
# up on a survivor rather than parked on the holder.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-refocus.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-refocus.log" $WM

"$LINUX/whale" "$HERE/client-refocus.tcl" > "$HERE/refocus-leader.log" &
CA=$!
sleep 0.5
# The two bystanders outlive phase B below — the whole point of that
# phase is that a survivor is standing there to be refocused.
"$LINUX/whale" "$HERE/client.tcl" "ранний" 240x120 "#8ae234" "" "" 30 \
    > "$HERE/refocus-early.log" &
CC=$!
wait_client "$HERE/wm-refocus.log" 'ранний'
"$LINUX/whale" "$HERE/client.tcl" "поздний" 240x120 "#fcaf3e" "" "" 30 \
    > "$HERE/refocus-late.log" &
CB=$!

wait $CA
sleep 1

# --- phase B: a whole APPLICATION leaves at once. Four windows die in
# one burst, and the pick made when the first of them goes names a
# sibling that is already dead on the server — the aim is REFUSED and
# the focus stays parked on the holder. Nothing came after to notice:
# the sibling's own unmanage reads no dead end (::focused is 0 already,
# the server focus is neither None nor a frame) and repairs nothing, so
# the desk sat keyboard-dead beside a perfectly good window (lazarus-ide
# taking its four down, the owner 2026-08-19).
"$LINUX/whale" "$HERE/client-burst.tcl" 4 > "$HERE/refocus-burst.log" 2>&1 &
CE=$!
wait_client "$HERE/wm-refocus.log" 'стая3'
wait $CE
sleep 1

kill $WM 2>/dev/null
kill $CB $CC 2>/dev/null

# Actors are identified by MANAGE ORDER (the 0.5 s spacings above make it
# deterministic): leader, early, late, dialog. Client-side winfo id would
# not do — it names Tk's inner window, the WM manages the wrapper.
set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-refocus.log")
AID=$1; CID=$2; BID=$3; DID=$4
echo "--- actors: leader=$AID early=$CID late=$BID dialog=$DID"
echo "--- unmanages and focus moves:"
grep -E 'unmanaged|focus ->' "$HERE/wm-refocus.log"

echo "--- verdict"
# A leftover WM from an earlier run would take the redirect and this run
# would measure somebody else's behavior.
if grep -q 'BadAccess request=2' "$HERE/wm-refocus.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$AID" ] || [ -z "$DID" ] || [ -z "$BID" ]; then
    echo "FAIL: missing actor ids (leader=$AID dialog=$DID late=$BID)"
fi
awk -v a="$AID" -v d="$DID" -v b="$BID" '
/^WM: unmanaged 0x/ { last = $3; sub(/,$/, "", last) }
# the REFUSED variant of the focus line is a failed attempt, not a move
/^WM: focus -> 0x/ && !/REFUSED/ { if (last != "") { got[last] = $4; last = "" } }
END {
    bad = 0
    if (got[d] != a) { print "FAIL: dialog close refocused \"" got[d] "\", want leader " a; bad = 1 }
    if (got[a] != b) { print "FAIL: leader death refocused \"" got[a] "\", want most recent " b; bad = 1 }
    if (!bad) print "OK: dialog close -> leader; leader death -> most recently focused"
}' "$HERE/wm-refocus.log"
# Phase B reads in two halves, and the first is what keeps the second
# from passing vacuously: the trap must have been ARMED (the server
# refused the aim the pick made), and the desk must then have RECOVERED
# — an honest focus line standing after that refusal.
if grep -q 'REFUSED by server' "$HERE/wm-refocus.log"; then
    echo "OK: the burst armed the trap — an aim at a doomed sibling was refused"
    # No refusal may be left DANGLING — the last one in the log has to
    # be followed by an honest aim, not just some earlier one.
    if awk '/REFUSED by server/ { pending = 1; next }
            /^WM: focus -> 0x/  { pending = 0 }
            END { exit pending }' "$HERE/wm-refocus.log"; then
        echo "OK: ...and the refused aim was retried onto a live window"
    else
        echo "FAIL: the refused aim was never retried — the keyboard is left\
 parked on the holder with live windows standing"
    fi
else
    echo "FAIL: phase B armed nothing — no refused aim, so it proves nothing"
fi
