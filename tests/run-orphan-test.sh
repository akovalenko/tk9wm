#!/bin/sh
# Regression for the children a restart leaves us holding.
#
# execv keeps the pid, and keeping the pid keeps the CHILDREN — what it
# does not keep is Tcl's record of them, which lived in the memory the
# exec threw away. Nothing waits for them afterwards, so each becomes a
# zombie for good on its way out. The owner's desk, 2026-07-31: 38 of
# them after a day of restart chords, with a whale among them for every
# stale ui host that handed its applets over and left — which is why
# the ui looked like the culprit when it was only the regular victim.
#
# Both halves are driven here, because the second is what makes the
# first safe:
#
#   1. a child of the OLD image, killed after the restart, is waited
#      for by the new one — no zombie left behind;
#   2. a child the NEW image spawned itself is NOT on that list. It is
#      Tcl's to reap inside the next exec, and a stolen exit status is
#      how an `exec` or a pipe's `close` starts failing with "no child
#      processes".
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/orphan-config"
mkdir -p "$HERE/orphan-config"
export ORPHAN_PIDS="$HERE/orphan.pids"
rm -f "$ORPHAN_PIDS"

# Every image the desk runs leaves one long-lived child behind and says
# which. The first line is thus image 1's — the one that outlives the
# restart and has nobody left to wait for it; the second is image 2's
# own, which must stay out of the inherited list.
cat > "$HERE/orphan-config/tk9wm.tcl" <<'EOF'
set p [exec sleep 600 &]
set f [open $::env(ORPHAN_PIDS) a]
puts $f $p
close $f
EOF

cat > "$HERE/orphan-config/q-orphans.tcl" <<'EOF'
set ::orphans
EOF
cat > "$HERE/orphan-config/q-reap.tcl" <<'EOF'
reap-orphans
EOF
ask() { "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$1"; }
# state_of <pid> — R/S/Z straight from the kernel, empty when the pid is
# gone entirely. A reaped child leaves nothing; an unwaited-for one
# leaves a Z.
state_of() { ps -o stat= -p "$1" 2>/dev/null | tr -d ' ' | cut -c1; }

XDG_CONFIG_HOME="$HERE/orphan-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/orphan-1.log" 2>&1 &
WM=$!
sleep 2
PID1=$(sed -n 1p "$ORPHAN_PIDS")

# --- the restart: same pid, fresh image, PID1 still hanging off it
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
sleep 3
PID2=$(sed -n 2p "$ORPHAN_PIDS")
ORPHANS=$(ask "$HERE/orphan-config/q-orphans.tcl")

# --- kill the inherited one: nobody but the new image can bury it
kill "$PID1" 2>/dev/null
sleep 1
BEFORE=$(state_of "$PID1")
ask "$HERE/orphan-config/q-reap.tcl" >/dev/null
sleep 0.5
AFTER=$(state_of "$PID1")
LEFT=$(ask "$HERE/orphan-config/q-orphans.tcl")

kill "$WM" "$PID1" "$PID2" 2>/dev/null
sleep 0.5

echo "--- what came with the pid:"
grep -E 'came with the pid|reaped .* inherited' "$HERE/orphan-1.log"

echo "--- verdict"
if [ -n "$PID1" ] && [ -n "$PID2" ] && [ "$PID1" != "$PID2" ]; then
    echo "OK: two images ran, each with a child of its own ($PID1, $PID2)"
else
    echo "FAIL: the images did not both start (pids «$PID1», «$PID2»)"
fi
if [ "$ORPHANS" = "$PID1" ]; then
    echo "OK: the fresh image adopted exactly the child it inherited"
else
    echo "FAIL: adopted «$ORPHANS», want «$PID1»"
fi
case " $ORPHANS " in
    *" $PID2 "*) echo "FAIL: it also grabbed its OWN child $PID2 —\
 that status is Tcl's to collect" ;;
    *) echo "OK: its own child stayed out of the list" ;;
esac
if [ "$BEFORE" = Z ]; then
    echo "OK: the inherited child died unwaited-for, as a zombie"
else
    echo "FAIL: state «$BEFORE» before the reap (want Z) —\
 this run measured nothing"
fi
if [ -z "$AFTER" ]; then
    echo "OK: ...and the poll buried it"
else
    echo "FAIL: still «$AFTER» after reap-orphans — the zombie stayed"
fi
if [ -z "$LEFT" ]; then
    echo "OK: nothing left to watch"
else
    echo "FAIL: the list still holds «$LEFT»"
fi
if grep -q '1 child(ren) came with the pid' "$HERE/orphan-1.log"; then
    echo "OK: the adoption said so in the log"
else
    echo "FAIL: no adoption line in the log"
fi
check_invariants "$HERE/orphan-1.log"
