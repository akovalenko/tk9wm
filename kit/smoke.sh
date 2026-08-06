#!/bin/sh
# smoke.sh — run a wrapped tk9wm as a live window manager on a
# throwaway Xvfb, give it one client, take a screenshot. The config it
# writes declares a panel on purpose: a panel is what pulls treectrl
# out of the kit's own lib/, so a run that shows a panel has proved
# both shared libraries load from inside the wrapper.
#
#   TCLKIT=…/tclkit ./kit/smoke.sh ./kit/tk9wm.bin          the starpack
#   TCLKIT=…/tclkit ./kit/smoke.sh "$TCLKIT" kit/tk9wm.kit  the starkit
#
# The client is run by TCLKIT (any Tcl/Tk 9 will do); with TCLKIT
# unset it falls back to the first word of the command under test,
# which is right for the starkit form and for a starpack that can also
# act as an interpreter.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
DISP=${DISP:-:67}
export DISPLAY=$DISP
rm -f "/tmp/.X${DISP#:}-lock" "/tmp/.X11-unix/X${DISP#:}"
Xvfb "$DISP" -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1.5

rm -rf "$HERE/smoke-config"
mkdir -p "$HERE/smoke-config"
cat > "$HERE/smoke-config/tk9wm.tcl" <<'EOF'
set-panel-side left
action терм {match {filter -title {кит*}} launch {exec true}}
panel-button терм
panel-button ещё {}
# a chord for the restart leg below: a wrapped manager re-execs itself
# differently from a checkout (a starpack IS its application, a starkit
# is a file its interpreter has to be told about again), and this is
# where that is exercised. Bound here rather than sent as a
# ClientMessage because tools/send-restart.tcl wants cffi, which a
# stock tclkit has no reason to carry.
wm-bind {<Super>t x} Restart
EOF

XDG_CONFIG_HOME="$HERE/smoke-config" "$@" > "$HERE/smoke-wm.log" 2>&1 &
WM=$!
sleep 2
"${TCLKIT:-$1}" "$ROOT/tests/client.tcl" \
    кит-жилец 240x120 '#729fcf' '' '' 12 > "$HERE/smoke-client.log" 2>&1 &
CL=$!
sleep 2
import -display "$DISP" -window root "$HERE/smoke.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/smoke.png"
xdotool key super+t; sleep 0.4; xdotool key x
sleep 3
# the ui host, asked for by the (restarted) desk over the send door,
# then asked POINT-BLANK which font engine it runs: the kit's Tk must
# arrive in the host too — on a stock -tk tclkit it would otherwise
# draw core fonts into every applet, and on a Tk-less one it would
# have no Tk at all (-ui-host in mkkit.sh is what makes this true).
# A wrapped desk answers to tk9wm — its mkkit-claimed name (a starpack
# left to the boot's accidents said «main.tcl») — the host, to tk9wm-ui.
printf 'applet about\n' > "$HERE/smoke-config/q.tcl"
"${TCLKIT:-$1}" "$ROOT/tools/send-eval.tcl" tk9wm \
    "$HERE/smoke-config/q.tcl" >/dev/null 2>&1 || true
sleep 3
printf 'tk::pkgconfig get fontsystem\n' > "$HERE/smoke-config/q.tcl"
HOSTFS=$("${TCLKIT:-$1}" "$ROOT/tools/send-eval.tcl" tk9wm-ui \
    "$HERE/smoke-config/q.tcl" 2>/dev/null || true)
# read the client's liveness BEFORE we kill it ourselves — asking after
# is asking about our own handiwork (it read as a failed restart)
kill -0 $CL 2>/dev/null && CLIENT_ALIVE=yes || CLIENT_ALIVE=no
kill $WM $CL 2>/dev/null || true
sleep 0.3

echo "--- verdict"
if grep -q 'redirect armed' "$HERE/smoke-wm.log"; then
    echo "OK: the shim loaded out of the wrapper (redirect armed)"
else
    echo "FAIL: no redirect — the shim did not load"
fi
if grep -q 'panel default up' "$HERE/smoke-wm.log"; then
    echo "OK: treectrl loaded out of the wrapper (the panel is up)"
else
    echo "FAIL: no panel — treectrl did not load"
fi
if grep -q 'managed 0x' "$HERE/smoke-wm.log"; then
    echo "OK: a client was framed and managed"
else
    echo "FAIL: nothing was managed"
fi
if [ "$(grep -c 'redirect armed' "$HERE/smoke-wm.log")" -ge 2 ] \
        && [ "$CLIENT_ALIVE" = yes ]; then
    echo "OK: a restart in place came back up, client and all"
else
    echo "FAIL: the wrapped manager did not restart in place"
fi
if grep -q 'applet about up' "$HERE/smoke-wm.log"; then
    echo "OK: the applet came up in a spawned host"
else
    echo "FAIL: no applet — the ui host did not come up"
fi
if [ "$HOSTFS" = xft ]; then
    echo "OK: the ui host runs the kit's own Tk (fontsystem=xft)"
else
    echo "FAIL: the ui host's font engine is «$HOSTFS», not xft"
fi
if grep -q 'handler error' "$HERE/smoke-wm.log"; then
    echo "FAIL: handler errors:"; grep 'handler error' "$HERE/smoke-wm.log"
fi
