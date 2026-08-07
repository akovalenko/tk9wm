#!/bin/sh
# Regression for the live bug of 2026-07-28 (display :7): the session
# would suddenly start following the pointer — keys going wherever the
# mouse hovered — with a globally-active Wine window on screen, and it
# never recovered. The probe caught it red-handed: focus=0x1 revert=1,
# i.e. PointerRoot/RevertToPointerRoot.
#
# The culprit was the WM's own toolkit. Tk keeps an implicit-focus
# mechanism for focus-follows-pointer environments (generic/tkFocus.c):
# on a crossing into any Tk window whose xcrossing.focus flag is set it
# claims the focus, and on the matching LeaveNotify it calls
# XSetInputFocus(PointerRoot, RevertToPointerRoot, CurrentTime) — line
# 506, the exact constants the probe reported. Every frame, grip and
# panel of this WM is a Tk window, so a mouse sweep at the wrong moment
# was enough, and step 26's PointerRoot parking made those moments
# routine.
#
# What must hold now, whatever nukes the focus (Tk, an outer Xephyr
# crossing, a stray client):
#   - the WM SEES it (FocusIn on root, detail PointerRoot/None),
#   - it parks the focus on a real holder — the display never stays in
#     pointer-follows mode,
#   - and it re-aims at the window that deserves the focus: for a
#     globally-active client, a fresh invitation issued AFTER the park,
#     so the client's answer cannot be dropped as stale.
# set-pointerroot.tcl fires the nuke exactly as Tk does.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/gareset-config"
mkdir -p "$HERE/gareset-config"
: > "$HERE/gareset-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/gareset-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-gareset.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" обычный 240x120 "#729fcf" "" "" 40 &
CB=$!
sleep 1.5

"$LINUX/whale" "$HERE/ga-client.tcl" сброс-га > "$HERE/gareset-client.log" 2>&1 &
GA=$!
sleep 2                # the ga window is focused by its invitation

echo "--- before the nuke:"
"$LINUX/whale" "$TOOLS/probe-focus.tcl"

# The nuke: exactly what Tk does on its implicit LeaveNotify.
"$LINUX/whale" "$TOOLS/set-pointerroot.tcl"
sleep 1.5

AFTER=$("$LINUX/whale" "$TOOLS/probe-focus.tcl")
xdotool key z          # keys must reach the ga window again
sleep 0.5
GAID=$(sed -n 's/^GACLIENT: up, window \(0x[0-9a-f]*\).*/\1/p' "$HERE/gareset-client.log" | head -1)
ACTIVE=$(xprop -root _NET_ACTIVE_WINDOW | sed -n 's/.*window id # \(0x[0-9a-f]*\).*/\1/p')

# Round two, the ordinary path: hand the focus to the plain client and
# nuke again. No invitation is involved there — the WM parks and then
# sets the focus itself — and the repair must be just as complete.
xdotool keydown alt key Tab; xdotool keyup alt
sleep 1
"$LINUX/whale" "$TOOLS/set-pointerroot.tcl"
sleep 1.5
AFTER2=$("$LINUX/whale" "$TOOLS/probe-focus.tcl")
ACTIVE2=$(xprop -root _NET_ACTIVE_WINDOW | sed -n 's/.*window id # \(0x[0-9a-f]*\).*/\1/p')

kill $WM $GA $CB 2>/dev/null

echo "--- client lines:"
cat "$HERE/gareset-client.log"
echo "--- WM lines:"
grep -E 'PointerRoot|None|parking|invitation|holder|landed' "$HERE/wm-gareset.log"
echo "--- focus after the nuke: $AFTER"
echo "--- focus after the plain-client nuke: $AFTER2 (active $ACTIVE2)"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-gareset.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'focus fell to PointerRoot' "$HERE/wm-gareset.log"; then
    echo "OK: the WM saw the display fall into pointer-follows mode"
else
    echo "FAIL: the nuke went unnoticed — the WM is blind to it"
fi
case "$AFTER" in
    *"focus=0x1 "*)
        echo "FAIL: still PointerRoot — the session is following the pointer" ;;
    *"focus=0x0 "*)
        echo "FAIL: focus is None — the keyboard is dead" ;;
    *)  echo "OK: the focus rests on a real window again ($AFTER)" ;;
esac
if [ "$(grep -c 'GACLIENT: invited' "$HERE/gareset-client.log")" -ge 2 ]; then
    echo "OK: the ga window was re-invited after the repair"
else
    echo "FAIL: no invitation followed the repair"
fi
if grep -q 'GACLIENT: answer DROPPED' "$HERE/gareset-client.log"; then
    echo "FAIL: an answer was dropped — the park/invite order is wrong"
else
    echo "OK: no answer was ever dropped (the park preceded the invitation)"
fi
if [ "$(grep -c 'GACLIENT: key' "$HERE/gareset-client.log")" -ge 1 ]; then
    echo "OK: keys flow into the ga window after the repair"
else
    echo "FAIL: no key reached the ga window after the repair"
fi
if [ "$ACTIVE" = "$GAID" ]; then
    echo "OK: _NET_ACTIVE_WINDOW follows the repaired focus ($ACTIVE)"
else
    echo "FAIL: active is «$ACTIVE», want $GAID"
fi
# round two: the ordinary (non globally-active) client
case "$AFTER2" in
    *"focus=0x1 "*|*"focus=0x0 "*)
        echo "FAIL: the plain-client nuke left the focus at $AFTER2" ;;
    *)  echo "OK: the plain client got its focus back ($AFTER2)" ;;
esac
F2=$(echo "$AFTER2" | sed -n 's/.*focus=\(0x[0-9a-f]*\).*/\1/p')
if [ "$ACTIVE2" = "$F2" ]; then
    echo "OK: _NET_ACTIVE_WINDOW agrees with the real focus ($ACTIVE2)"
else
    echo "FAIL: active «$ACTIVE2» disagrees with the focus «$F2»"
fi
if grep -q 'handler error' "$HERE/wm-gareset.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-gareset.log"
fi
