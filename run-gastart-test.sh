#!/bin/sh
# Regression for the manage-time invitation wedge (live report,
# 2026-07-28: smsrc under Wine LOOKED active at startup while the
# keys kept flowing into the previous xterm). A manage-time
# WM_TAKE_FOCUS carries whatever time the WM's clock has, and the
# clock ticks only on grabbed keys/buttons — typing INTO a window is
# invisible, so the stamp is stale and Wine's focus-stealing guard
# refuses the invitation; with no retry the wedge was permanent.
# Three cures, all exercised here: PropertyNotify feeds the clock,
# an unanswered invitation is re-invited (capped), and an EWMH
# _NET_ACTIVE_WINDOW activation request (Wine re-asks by itself) is
# honored. ga-client's reject mode models the refusing guard.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:71
rm -f /tmp/.X71-lock /tmp/.X11-unix/X71
Xvfb :71 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/gastart-config"
mkdir -p "$HERE/gastart-config"
: > "$HERE/gastart-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/gastart-config" \
    "$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-gastart.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/ga-client.tcl" старт-га 1 > "$HERE/gastart-client.log" 2>&1 &
GA=$!
sleep 1.5              # manage: invite -> REJECTED -> re-invite -> honored

xdotool key x          # keys must flow into the ga window now
sleep 0.5

"$LINUX/whale" "$HERE/client.tcl" обычный 240x120 "#729fcf" "" "" 20 &
CB=$!
sleep 1.5              # the plain client takes the focus away

GAID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-gastart.log" | head -1)
xdotool windowactivate "$GAID" 2>/dev/null \
    || echo "DRIVER: xdotool windowactivate failed"
sleep 1                # activation request -> invite -> honored

ACTIVE=$(xprop -root _NET_ACTIVE_WINDOW | sed -n 's/.*window id # \(0x[0-9a-f]*\).*/\1/p')

kill $WM $GA $CB 2>/dev/null

echo "--- client lines:"
cat "$HERE/gastart-client.log"
echo "--- WM lines:"
grep -E 'invitation|re-inviting|activation request' "$HERE/wm-gastart.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-gastart.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'GACLIENT: invitation REJECTED' "$HERE/gastart-client.log"; then
    echo "OK: the guard refused the manage-time invitation"
else
    echo "FAIL: the reject mode never fired — the scenario is void"
fi
if grep -q 'unanswered — re-inviting' "$HERE/wm-gastart.log"; then
    echo "OK: the WM noticed and re-invited"
else
    echo "FAIL: no re-invitation line"
fi
T1=$(sed -n 's/^GACLIENT: invitation REJECTED t=\([0-9]*\).*/\1/p' "$HERE/gastart-client.log" | head -1)
T2=$(sed -n 's/^GACLIENT: invited t=\([0-9]*\).*/\1/p' "$HERE/gastart-client.log" | head -1)
if [ -n "$T1" ] && [ -n "$T2" ] && [ "$T2" -gt "$T1" ]; then
    echo "OK: the re-invitation carried a fresher stamp ($T1 -> $T2)"
else
    echo "FAIL: stamps did not freshen (rejected t=$T1, invited t=$T2)"
fi
if grep -q 'GACLIENT: answer DROPPED' "$HERE/gastart-client.log"; then
    echo "FAIL: an answer was clobbered"
else
    echo "OK: no answer was clobbered"
fi
if grep -q 'GACLIENT: key' "$HERE/gastart-client.log"; then
    echo "OK: keys flow after the manage-time recovery"
else
    echo "FAIL: no key reached the client"
fi
if grep -q "activation request for $GAID" "$HERE/wm-gastart.log" \
   && [ "$ACTIVE" = "$GAID" ]; then
    echo "OK: the activation request was honored, active ends on $GAID"
else
    echo "FAIL: activation request path (active=«$ACTIVE», want $GAID)"
fi
if grep -q 'handler error' "$HERE/wm-gastart.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-gastart.log"
fi
