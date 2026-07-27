#!/bin/sh
# Regression for the refocus pick (WM_TRANSIENT_FOR + focus history).
# Scenario: leader A, then C, then B receive focus in turn; A pops a
# transient dialog D (focused). Closing D must refocus A — the dialog's
# LEADER — and not B, the most recently focused bystander (the smsrc
# observation: an app does not refocus its main window itself, that is
# the WM's job). Then A exits, and the focus history must hand focus to
# B (most recent living window), not an arbitrary managed one.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:77
rm -f /tmp/.X77-lock /tmp/.X11-unix/X77
Xvfb :77 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-refocus.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client-refocus.tcl" > "$HERE/refocus-leader.log" &
CA=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "ранний" 240x120+30+30 "#8ae234" \
    > "$HERE/refocus-early.log" &
CC=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "поздний" 240x120+30+30 "#fcaf3e" \
    > "$HERE/refocus-late.log" &
CB=$!

wait $CA
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
