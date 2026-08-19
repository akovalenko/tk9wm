#!/bin/sh
# Regression for ICCCM 2.8 manager replacement, both directions.
#
#   1. a plain start owns WM_S<n> and says so;
#   2. a second instance WITHOUT -replace refuses, names the owner, and
#      leaves the running desk untouched;
#   3. a second instance WITH -replace takes the desk: the first stands
#      down, its client SURVIVES the handover and is adopted by the
#      newcomer (which is the whole point — a replacement that costs
#      the desk its windows is a reboot with extra steps);
#      — and says so in its exit code, which is what lets a .xsession
#      tell "somebody took the desk" from "the user asked to leave";
#   4. the restart chord still works while we own the selection (execv
#      drops the X connection, so the fresh instance can find its own
#      corpse still holding it — restart-wm passes -replace for that).
#
# fvwm3, when present, is the foreign half: it speaks the same protocol
# and its --replace is a real second opinion about ours.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/replace-config"
mkdir -p "$HERE/replace-config"
cat > "$HERE/replace-config/tk9wm.tcl" <<'EOF'
# nothing to configure — the stock desk is what this test measures
EOF

# wm_start <pidvar> <logfile> [args...] — started in THIS shell, so
# `wait` can be asked for the exit code later; $(...) would put them in
# a subshell and out of reach.
wm_start() {
    var=$1; log=$2; shift 2
    XDG_CONFIG_HOME="$HERE/replace-config" \
        "$LINUX/whale" "$WMTCL" "$@" > "$log" 2>&1 &
    eval "$var=$!"
}

# code_of <pid> — the exit code of a manager that should be gone by now.
# A watchdog rather than a bare `wait`: one that did NOT leave would
# hang this script forever, and 143 (killed) is a legible failure.
code_of() {
    ( sleep 15; kill "$1" 2>/dev/null ) &
    wd=$!
    wait "$1"; c=$?
    kill $wd 2>/dev/null
    return $c
}

# --- 1. the first manager, with a client on its desk
wm_start WM1 "$HERE/replace-1.log"
wait_wm "$HERE/replace-1.log" $WM1
"$LINUX/whale" "$HERE/client.tcl" сменщик 240x120 "#729fcf" "" "" 40 \
    > "$HERE/replace-client.log" 2>&1 &
CL=$!
wait_client "$HERE/replace-1.log" 'сменщик'

# --- 2. a newcomer with no -replace must refuse and change nothing —
# the refusal is its own word in its own log, so wait for that
wm_start WM2 "$HERE/replace-2.log"
wait_for 15 grep -q 'already owns' "$HERE/replace-2.log" \
    || echo "note: the newcomer never said its refusal"
kill -0 $WM1 2>/dev/null && FIRST_ALIVE=yes || FIRST_ALIVE=no
code_of $WM2; SECOND_CODE=$?

# --- 3. ...and one with -replace must take the desk
wm_start WM3 "$HERE/replace-3.log" -replace
wait_wm "$HERE/replace-3.log" $WM3
# The ADOPTION is a later step than the config line wait_wm answers at —
# the sweep that reframes the outgoing manager's orphans runs after the
# layers are in. Waiting for the config line and then asking about
# adopted windows measures a moment that has not happened yet (see leg 5,
# where it was doing exactly that).
wait_for 15 grep -q 'adopting existing window' "$HERE/replace-3.log" \
    || echo "note: the replacement never said it adopted anything"
code_of $WM1; FIRST_CODE=$?
kill -0 $CL  2>/dev/null && CLIENT_ALIVE=yes || CLIENT_ALIVE=no
import -display "$DISPLAY" -window root "$HERE/replace-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/replace-test.png"

# --- 4. restart in place, with the selection in our hands. execv keeps
# the pid and drops the X connection, so the fresh instance can find the
# owner window of the manager it IS still holding WM_S<n> — restart-wm
# passes -replace exactly for that, and this is the check that it does.
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
# execv keeps the pid and the log fd: the second life announces
# itself with a second config line in the SAME file
wait_for 15 sh -c "[ \$(grep -c 'WM: config /' \"$HERE/replace-3.log\") -ge 2 ]" \
    || echo "note: no second config line after the in-place restart"

# --- 5. the foreign half. fvwm3 speaks the same ICCCM protocol and is
# not ours, which is the only kind of agreement about a protocol worth
# having: it must be able to take the desk from us, and we from it,
# with the client living through both handovers. Skipped, loudly, where
# there is no fvwm3.
FOREIGN=skip
if command -v fvwm3 >/dev/null 2>&1; then
    FOREIGN=run
    cat > "$HERE/replace-config/fvwmrc" <<'FVEOF'
DesktopSize 1x1
Style * BorderWidth 4
FVEOF
    fvwm3 -f "$HERE/replace-config/fvwmrc" --replace \
        > "$HERE/replace-fvwm.log" 2>&1 &
    FV=$!
    sleep 4
    code_of $WM3; THIRD_CODE=$?
    kill -0 $CL  2>/dev/null && CLIENT_AFTER_FVWM=yes || CLIENT_AFTER_FVWM=no
    wm_start WM4 "$HERE/replace-4.log" -replace
    wait_wm "$HERE/replace-4.log" $WM4
    # Same wait as leg 3, and here it is load-bearing: nothing else in
    # this leg blocks, so the log was being read — and the manager
    # killed — a few lines before the sweep it is asked about. The
    # adoption always happened; the test simply never let it (measured,
    # 2026-08-19).
    wait_for 15 grep -q 'adopting existing window' "$HERE/replace-4.log" \
        || echo "note: we never said we adopted anything back from fvwm3"
    kill -0 $FV 2>/dev/null && FVWM_STILL=yes || FVWM_STILL=no
    kill -0 $CL 2>/dev/null && CLIENT_AFTER_US=yes || CLIENT_AFTER_US=no
    kill $WM4 $FV 2>/dev/null
fi

kill $WM3 $CL 2>/dev/null
sleep 0.5

echo "--- first manager:"
grep -E 'redirect armed|WM_S|standing down|released' "$HERE/replace-1.log" | head
echo "--- refused newcomer:"
grep -E 'already owns|redirect armed' "$HERE/replace-2.log" | head
echo "--- replacing newcomer:"
grep -E 'asking|redirect armed|adopt|restart' "$HERE/replace-3.log" | head

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/replace-1.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'redirect armed on root .*WM_S. owner 0x' "$HERE/replace-1.log"; then
    echo "OK: the first manager owns the selection"
else
    echo "FAIL: the first manager did not announce an owner window"
fi
if grep -q 'already owns WM_S' "$HERE/replace-2.log"; then
    echo "OK: a newcomer without -replace refused, naming the owner"
else
    echo "FAIL: the second manager did not refuse the way it should"
fi
if [ "$FIRST_ALIVE" = yes ] && [ "$SECOND_CODE" = 1 ]; then
    echo "OK: the refusal exited 1 and left the running desk alone"
else
    echo "FAIL: after the refusal first alive=$FIRST_ALIVE,\
 refused manager exited $SECOND_CODE (want 1)"
fi
if grep -q 'standing down' "$HERE/replace-1.log"; then
    echo "OK: the first manager was asked and stood down"
else
    echo "FAIL: the first manager never saw a SelectionClear"
fi
if [ "$FIRST_CODE" = 3 ]; then
    echo "OK: ...and left with code 3 — the one a .xsession reads as\
 «replaced, do not end the session»"
else
    echo "FAIL: the replaced manager exited $FIRST_CODE (want 3)"
fi
if grep -q 'redirect armed' "$HERE/replace-3.log"; then
    echo "OK: the replacement holds the desk"
else
    echo "FAIL: the replacement never armed the redirect"
fi
if [ "$CLIENT_ALIVE" = yes ] \
        && grep -q 'managed 0x' "$HERE/replace-3.log"; then
    echo "OK: the client survived the handover and was adopted"
else
    echo "FAIL: client alive=$CLIENT_ALIVE, adoption:\
 $(grep -c 'managed 0x' "$HERE/replace-3.log") lines"
fi
if [ "$(grep -c 'redirect armed' "$HERE/replace-3.log")" -ge 2 ]; then
    echo "OK: the restart chord came back up through its own selection"
else
    echo "FAIL: no second 'redirect armed' — the restart did not survive"
fi
if [ "$FOREIGN" = skip ]; then
    echo "SKIP: no fvwm3 — the foreign half of the protocol went untested"
else
    if [ "$THIRD_CODE" = 3 ] \
            && grep -q 'standing down' "$HERE/replace-3.log"; then
        echo "OK: fvwm3 --replace took the desk from us, and we let it (code 3)"
    else
        echo "FAIL: fvwm3 --replace did not get the desk (we exited $THIRD_CODE)"
    fi
    if [ "$FVWM_STILL" = no ] \
            && grep -q 'redirect armed' "$HERE/replace-4.log"; then
        echo "OK: ...and -replace took it back from fvwm3"
    else
        echo "FAIL: we did not take the desk back (fvwm still=$FVWM_STILL)"
    fi
    if [ "$CLIENT_AFTER_FVWM" = yes ] && [ "$CLIENT_AFTER_US" = yes ] \
            && grep -q 'adopting existing window' "$HERE/replace-4.log"; then
        echo "OK: the client lived through both foreign handovers"
    else
        echo "FAIL: client after fvwm=$CLIENT_AFTER_FVWM, after us=$CLIENT_AFTER_US"
    fi
fi
for f in 1 2 3 4; do
    [ -f "$HERE/replace-$f.log" ] || continue
    if grep -q 'handler error' "$HERE/replace-$f.log"; then
        echo "FAIL: handler errors in manager $f:"
        grep 'handler error' "$HERE/replace-$f.log"
    fi
done
