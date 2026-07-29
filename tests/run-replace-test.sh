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
#   4. the restart chord still works while we own the selection (execv
#      drops the X connection, so the fresh instance can find its own
#      corpse still holding it — restart-wm passes -replace for that).
#
# fvwm3, when present, is the foreign half: it speaks the same protocol
# and its --replace is a real second opinion about ours.
. "$(dirname "$0")/common.sh"
export DISPLAY=:60
rm -f /tmp/.X60-lock /tmp/.X11-unix/X60
Xvfb :60 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/replace-config"
mkdir -p "$HERE/replace-config"
cat > "$HERE/replace-config/tk9wm.tcl" <<'EOF'
# nothing to configure — the stock desk is what this test measures
EOF

wm_start() {   # wm_start <logfile> [args...]
    log=$1; shift
    XDG_CONFIG_HOME="$HERE/replace-config" \
        "$LINUX/whale" "$WMTCL" "$@" > "$log" 2>&1 &
    echo $!
}

# --- 1. the first manager, with a client on its desk
WM1=$(wm_start "$HERE/replace-1.log")
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" сменщик 240x120 "#729fcf" "" "" 40 \
    > "$HERE/replace-client.log" 2>&1 &
CL=$!
sleep 1.5

# --- 2. a newcomer with no -replace must refuse and change nothing
WM2=$(wm_start "$HERE/replace-2.log")
sleep 1.5
kill -0 $WM1 2>/dev/null && FIRST_ALIVE=yes || FIRST_ALIVE=no
kill -0 $WM2 2>/dev/null && SECOND_ALIVE=yes || SECOND_ALIVE=no

# --- 3. ...and one with -replace must take the desk
WM3=$(wm_start "$HERE/replace-3.log" -replace)
sleep 3
kill -0 $WM1 2>/dev/null && FIRST_STILL=yes || FIRST_STILL=no
kill -0 $CL  2>/dev/null && CLIENT_ALIVE=yes || CLIENT_ALIVE=no
import -display :60 -window root "$HERE/replace-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/replace-test.png"

# --- 4. restart in place, with the selection in our hands. execv keeps
# the pid and drops the X connection, so the fresh instance can find the
# owner window of the manager it IS still holding WM_S<n> — restart-wm
# passes -replace exactly for that, and this is the check that it does.
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" :60
sleep 3

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
    kill -0 $WM3 2>/dev/null && THIRD_STILL=yes || THIRD_STILL=no
    kill -0 $CL  2>/dev/null && CLIENT_AFTER_FVWM=yes || CLIENT_AFTER_FVWM=no
    WM4=$(wm_start "$HERE/replace-4.log" -replace)
    sleep 4
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
if [ "$FIRST_ALIVE" = yes ] && [ "$SECOND_ALIVE" = no ]; then
    echo "OK: the refusal left the running desk alone"
else
    echo "FAIL: after the refusal first=$FIRST_ALIVE second=$SECOND_ALIVE"
fi
if grep -q 'standing down' "$HERE/replace-1.log"; then
    echo "OK: the first manager was asked and stood down"
else
    echo "FAIL: the first manager never saw a SelectionClear"
fi
if [ "$FIRST_STILL" = no ]; then
    echo "OK: ...and it is gone"
else
    echo "FAIL: the replaced manager is still running"
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
    if [ "$THIRD_STILL" = no ] \
            && grep -q 'standing down' "$HERE/replace-3.log"; then
        echo "OK: fvwm3 --replace took the desk from us, and we let it"
    else
        echo "FAIL: fvwm3 --replace did not get the desk (ours still=$THIRD_STILL)"
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
