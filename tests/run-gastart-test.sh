#!/bin/sh
# Regression for the manage-time invitation wedge (live report,
# 2026-07-28: smsrc under Wine LOOKED active at startup while the
# keys kept flowing into the previous xterm), now cured
# deterministically (step 32).
#
# Two properties are measured here, and neither involves a timer:
#
#  1. The manage-time invitation carries a stamp FETCHED from the
#     server at that moment (server-time), so it is newer than the
#     last focus change by construction and the client's answer
#     cannot arrive stale. Step 31 stamped it from an accumulated
#     clock and papered over the staleness with capped resends.
#  2. When a client refuses anyway (ga-client's stubborn reject mode
#     models a guard whose bar we cannot see), recovery is EVENT
#     DRIVEN: the client asks for activation itself with an EWMH
#     _NET_ACTIVE_WINDOW message — exactly what Wine does — and the
#     WM honors it. That path only exists because the WM no longer
#     publishes a window as active before it truly is: a client that
#     believes it is already the foreground never re-asks.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/gastart-config"
mkdir -p "$HERE/gastart-config"
: > "$HERE/gastart-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/gastart-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-gastart.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-gastart.log" $WM

# A plain client first, and typing INTO it: those keys go to the client,
# never through the WM's grabs, so a clock the WM keeps of its own is
# stale from here on. This is the live startup situation — a command
# typed in an xterm launches the app.
"$LINUX/whale" "$HERE/client.tcl" обычный 240x120 "#729fcf" "" "" 30 &
CB=$!
wait_client "$HERE/wm-gastart.log" 'обычный'
xdotool key a b c
sleep 0.3

# Round 1: an ordinary globally-active client arrives. Its invitation
# must be honored on the FIRST try — no retries exist any more.
"$LINUX/whale" "$HERE/ga-client.tcl" старт-га > "$HERE/gastart-client.log" 2>&1 &
GA=$!
sleep 1.5
xdotool key x          # keys must flow into the ga window now
sleep 0.5

# Round 2: a stubborn client that refuses its manage-time invitation
# outright and re-asks for activation itself, as Wine does.
"$LINUX/whale" "$HERE/ga-client.tcl" упрямый-га 1 > "$HERE/gastub-client.log" 2>&1 &
GB=$!
sleep 2
xdotool key y          # keys must flow into the stubborn one after recovery
sleep 0.5

ACTIVE=$(xprop -root _NET_ACTIVE_WINDOW | sed -n 's/.*window id # \(0x[0-9a-f]*\).*/\1/p')

kill $WM $GA $GB $CB 2>/dev/null

echo "--- plain ga client:"
cat "$HERE/gastart-client.log"
echo "--- stubborn ga client:"
cat "$HERE/gastub-client.log"
echo "--- WM lines:"
grep -E 'invitation|activation request|parking|landed' "$HERE/wm-gastart.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-gastart.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'GACLIENT: invited' "$HERE/gastart-client.log" \
   && ! grep -q 'REJECTED' "$HERE/gastart-client.log"; then
    echo "OK: the manage-time invitation was fresh on the first try"
else
    echo "FAIL: the manage-time invitation was refused or never arrived"
fi
if grep -q 'GACLIENT: answer honored' "$HERE/gastart-client.log"; then
    echo "OK: the answer was honored by the server"
else
    echo "FAIL: the server dropped the answer"
fi
if grep -q 'GACLIENT: key' "$HERE/gastart-client.log"; then
    echo "OK: keys flow into the ga window"
else
    echo "FAIL: no key reached the ga window"
fi
if grep -q 're-inviting' "$HERE/wm-gastart.log"; then
    echo "FAIL: a timer resend fired — the cure is supposed to be deterministic"
else
    echo "OK: no resends — the stamp was right the first time"
fi
if grep -q 'stubborn guard' "$HERE/gastub-client.log"; then
    echo "OK: the stubborn guard refused its invitation"
else
    echo "FAIL: the stubborn mode never fired — that scenario is void"
fi
if grep -q 'asked for activation myself' "$HERE/gastub-client.log" \
   && grep -q 'activation request for' "$HERE/wm-gastart.log"; then
    echo "OK: recovery came through the client's own activation request"
else
    echo "FAIL: the activation-request recovery path did not run"
fi
if grep -q 'GACLIENT: answer honored' "$HERE/gastub-client.log" \
   && grep -q 'GACLIENT: key' "$HERE/gastub-client.log"; then
    echo "OK: the stubborn client ended up focused, keys flowing"
else
    echo "FAIL: the stubborn client never got the focus back"
fi
GBID=$(sed -n 's/^GACLIENT: up, window \(0x[0-9a-f]*\).*/\1/p' "$HERE/gastub-client.log" | head -1)
if [ "$ACTIVE" = "$GBID" ]; then
    echo "OK: _NET_ACTIVE_WINDOW ends on the recovered window ($ACTIVE)"
else
    echo "FAIL: active is «$ACTIVE», want $GBID"
fi
if grep -q 'handler error' "$HERE/wm-gastart.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-gastart.log"
fi
