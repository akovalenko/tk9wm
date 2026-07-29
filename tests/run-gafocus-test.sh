#!/bin/sh
# Regression for the ICCCM globally-active focus model (Wine 10+:
# WM_HINTS input=False + WM_TAKE_FOCUS). The WM must only send the
# invitation and then leave the X focus alone — the client answers
# with XSetInputFocus stamped with the invitation's timestamp, and
# the server silently drops an answer older than the last focus
# change, so any competing focus op of the WM's kills it (the fvwm3
# war, refought here: step 28's set-then-invite left Wine's keyboard
# dead on the second switch). ga-client.tcl answers every invitation,
# reports honored/dropped, bumps the focus time after each honored
# answer (Wine's menu-like own traffic), and reports every KeyPress.
. "$(dirname "$0")/common.sh"
export DISPLAY=:72
rm -f /tmp/.X72-lock /tmp/.X11-unix/X72
Xvfb :72 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/gafocus-config"
mkdir -p "$HERE/gafocus-config"
: > "$HERE/gafocus-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/gafocus-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-gafocus.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/ga-client.tcl" > "$HERE/gafocus-client.log" 2>&1 &
GA=$!
sleep 1.5              # managed -> invitation #1

"$LINUX/whale" "$HERE/client.tcl" обычный 240x120 "#729fcf" "" "" 30 &
CB=$!
sleep 1.5              # the plain client holds the focus

alttab() { xdotool keydown alt key Tab; xdotool keyup alt; sleep 0.8; }
alttab                 # -> ga-client, invitation #2
alttab                 # -> plain client again
alttab                 # -> ga-client, invitation #3 (the live bug's
                       #    "second switch", after the menu-like bump)
xdotool key x          # keys must actually flow
sleep 0.8

ACTIVE=$(xprop -root _NET_ACTIVE_WINDOW | sed -n 's/.*window id # \(0x[0-9a-f]*\).*/\1/p')

kill $WM $GA $CB 2>/dev/null

echo "--- client lines:"
cat "$HERE/gafocus-client.log"
echo "--- WM focus lines:"
grep -E 'focus ->' "$HERE/wm-gafocus.log" | tail -8

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-gafocus.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
GAID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-gafocus.log" | head -1)
INV=$(grep -c 'GACLIENT: invited' "$HERE/gafocus-client.log")
HON=$(grep -c 'GACLIENT: answer honored' "$HERE/gafocus-client.log")
if [ "$INV" -ge 3 ] && [ "$HON" = "$INV" ]; then
    echo "OK: every invitation was answered and honored ($HON of $INV)"
else
    echo "FAIL: $INV invitations, $HON honored"
fi
if grep -q 'GACLIENT: answer DROPPED' "$HERE/gafocus-client.log"; then
    echo "FAIL: the server dropped an answer — the WM clobbered an invitation"
else
    echo "OK: no answer was clobbered"
fi
if grep -q 'GACLIENT: key' "$HERE/gafocus-client.log"; then
    echo "OK: keys flow after the second switch back"
else
    echo "FAIL: no key reached the client"
fi
if grep -q "focus -> $GAID: WM_TAKE_FOCUS invitation" "$HERE/wm-gafocus.log" \
   && ! grep -q "focus -> $GAID: sending WM_TAKE_FOCUS" "$HERE/wm-gafocus.log" \
   && ! grep -Eq "focus -> $GAID\$" "$HERE/wm-gafocus.log"; then
    echo "OK: the WM only ever invited the globally-active window"
else
    echo "FAIL: the WM touched the globally-active window's focus itself"
fi
if [ "$ACTIVE" = "$GAID" ]; then
    echo "OK: _NET_ACTIVE_WINDOW ends on the ga window ($ACTIVE)"
else
    echo "FAIL: _NET_ACTIVE_WINDOW is «$ACTIVE», want $GAID"
fi
if grep -q 'handler error' "$HERE/wm-gafocus.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-gafocus.log"
fi
