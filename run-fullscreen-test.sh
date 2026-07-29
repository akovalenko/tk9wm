#!/bin/sh
# Regression for EWMH fullscreen: the whole SCREEN, no decoration, and
# nothing of ours left standing on top of it.
#
# Three clients, because three different things are being proved. Our
# own client.tcl is the one with a KNOWN COLOR, so a screenshot can say
# whether it really covers the panel and the tray rather than merely
# claiming their geometry. Then xterm and kitty, unmodified and real:
# both look for _NET_WM_STATE_FULLSCREEN in _NET_SUPPORTED and, before
# this existed, went fullscreen by NOT ASKING — measured, they sent
# nothing at all and stayed their old size. They are here so the answer
# to "does it work" is not a mock of what they do.
#
# The desk carries a panel AND a tray, which is what makes the stacking
# question real: both are our own override-redirect top-levels that
# lift themselves whenever they rebuild or an icon docks.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:96
# kitty wants both, and refuses to start when it cannot write them.
# Under /tmp and not next to the test: they hold nothing worth reading
# afterwards, unlike every other artifact a run leaves here.
export XDG_CACHE_HOME=/tmp/tk9wm-fs-cache
export XDG_RUNTIME_DIR=/tmp/tk9wm-fs-run
rm -rf "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
mkdir -p "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
rm -f /tmp/.X96-lock /tmp/.X11-unix/X96
Xvfb :96 -screen 0 1024x768x24 +extension RENDER >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

CONF="$HERE/fullscreen-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
panel-button терм { launch {} }
set-tray on
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$HERE/wm.tcl" \
    > "$HERE/wm-fullscreen.log" 2>&1 &
WM=$!
sleep 1.5

SUPPORTED=$(xprop -root _NET_SUPPORTED | tr ',' '\n' | grep -c _NET_WM_STATE_FULLSCREEN)

"$LINUX/whale" "$HERE/client.tcl" "полноэкранный" 240x120 "#8ae234" "" "" 45 \
    > "$HERE/fullscreen-client.log" 2>&1 &
CA=$!
sleep 1.5
CID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-fullscreen.log" | head -1)

geo() { xwininfo -id "$1" | sed -n 's/^  -geometry \([0-9x+-]*\).*/\1/p'; }
size() { xwininfo -id "$1" | awk '/Width:/{w=$2} /Height:/{h=$2}
    /Absolute upper-left X:/{x=$4} /Absolute upper-left Y:/{y=$4}
    END{printf "%dx%d+%d+%d", w, h, x, y}'; }
state() { xprop -id "$1" _NET_WM_STATE 2>/dev/null | sed 's/.*= //'; }
px() { import -window root "$HERE/fs-shot.png" 2>/dev/null
       convert "$HERE/fs-shot.png" -format "%[pixel:p{$1,$2}]" info:; }

# The panel is at the bottom edge, the tray strip in its right corner.
# A pixel in each is what a fullscreen window has to have taken over.
BEFORE_SIZE=$(size "$CID")
BEFORE_PANEL=$(px 300 750)

# --- pass 1: the state, asked for from outside (wmctrl speaks plain EWMH)
wmctrl -i -r "$CID" -b add,fullscreen
sleep 1.5
FS_SIZE=$(size "$CID")
FS_STATE=$(state "$CID")
FS_PANEL=$(px 300 750)
FS_TRAY=$(px 1000 750)

# --- an icon docks while a window is fullscreen: the tray lifts itself
# for its own reasons, and must not come up over the window
"$LINUX/whale" "$HERE/tray-client.tcl" "#729fcf" > "$HERE/fullscreen-tray.log" 2>&1 &
CT=$!
sleep 2
DOCKED=$(grep -c '^WM: tray: docked' "$HERE/wm-fullscreen.log")
AFTERDOCK_PANEL=$(px 1000 750)

# --- pass 2: and back out again
wmctrl -i -r "$CID" -b remove,fullscreen
sleep 1.5
BACK_SIZE=$(size "$CID")
BACK_STATE=$(state "$CID")
BACK_PANEL=$(px 300 750)

# --- pass 3: the OTHER road in, the property already on the window at
# manage time. Tk's `wm attributes -fullscreen` on an unmapped toplevel
# writes it there; the terminals below were measured NOT doing this
# (they map first and send the message), so without this client the
# manage-time path would go untested.
"$LINUX/whale" "$HERE/fs-client.tcl" "премап" "#ad7fa8" 25 \
    > "$HERE/fullscreen-premap.log" 2>&1 &
CP=$!
sleep 2.5
PREMAP=$(grep -c 'asked to start fullscreen' "$HERE/wm-fullscreen.log")
PMWIN=$(sed -n 's/^WM: \(0x[0-9a-f]*\) asked to start fullscreen/\1/p' \
    "$HERE/wm-fullscreen.log" | tail -1)
PM_SIZE=""
[ -n "$PMWIN" ] && PM_SIZE=$(size "$PMWIN")
kill $CP 2>/dev/null
sleep 1

# --- pass 4: the real terminals, unmodified, each asking as it does
timeout 30 xterm -fullscreen -geometry 40x10 -e sh -c 'sleep 25' \
    >/dev/null 2>&1 &
sleep 3
XTWIN=$(xdotool search --class xterm 2>/dev/null | tail -1)
XT_SIZE=""; XT_STATE=""
[ -n "$XTWIN" ] && XT_SIZE=$(size "$XTWIN") && XT_STATE=$(state "$XTWIN")

timeout 30 kitty --start-as fullscreen -o confirm_os_window_close=0 \
    sh -c 'sleep 25' > "$HERE/fullscreen-kitty.log" 2>&1 &
sleep 6
KTWIN=$(xdotool search --class kitty 2>/dev/null | tail -1)
KT_SIZE=""; KT_STATE=""
[ -n "$KTWIN" ] && KT_SIZE=$(size "$KTWIN") && KT_STATE=$(state "$KTWIN")

import -window root "$HERE/fullscreen-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/fullscreen-test.png"

pkill -f 'sleep 25' 2>/dev/null
kill $CA $CT 2>/dev/null
sleep 0.5
kill $WM 2>/dev/null
sleep 0.5

echo "--- client $CID: $BEFORE_SIZE -> $FS_SIZE -> $BACK_SIZE"
echo "--- state while fullscreen: «$FS_STATE», after: «$BACK_STATE»"
echo "--- panel pixel: before=$BEFORE_PANEL fullscreen=$FS_PANEL back=$BACK_PANEL"
echo "--- tray pixel: fullscreen=$FS_TRAY, after an icon docked=$AFTERDOCK_PANEL"
echo "--- pre-map client $PMWIN: $PM_SIZE (manage-time property, $PREMAP seen)"
echo "--- xterm $XTWIN: $XT_SIZE «$XT_STATE»"
echo "--- kitty $KTWIN: $KT_SIZE «$KT_STATE»"
grep -E 'WM: (fullscreen|_NET_WM_STATE)' "$HERE/wm-fullscreen.log"

echo "--- verdict"
if [ "$SUPPORTED" = 1 ]; then
    echo "OK: _NET_WM_STATE_FULLSCREEN is advertised in _NET_SUPPORTED"
else
    echo "FAIL: the atom is not in _NET_SUPPORTED — no client will ever ask"
fi
if [ "$FS_SIZE" = "1024x768+0+0" ]; then
    echo "OK: the fullscreen client got the whole SCREEN, panel and all"
else
    echo "FAIL: fullscreen geometry «$FS_SIZE», want 1024x768+0+0"
fi
case "$FS_STATE" in
    *_NET_WM_STATE_FULLSCREEN*) echo "OK: ...and the state is published on the window" ;;
    *) echo "FAIL: _NET_WM_STATE is «$FS_STATE» while fullscreen" ;;
esac
case "$FS_PANEL" in
    *"138,226,52"*) echo "OK: ...and it really covers the panel (the pixel is the client)" ;;
    *) echo "FAIL: the panel pixel is $FS_PANEL, not the client — the strip is on top" ;;
esac
case "$FS_TRAY" in
    *"138,226,52"*) echo "OK: ...and the tray strip too" ;;
    *) echo "FAIL: the tray pixel is $FS_TRAY, not the client" ;;
esac
if [ "$DOCKED" -ge 1 ] 2>/dev/null; then
    case "$AFTERDOCK_PANEL" in
        *"138,226,52"*) echo "OK: an icon docking did not lift the tray back over it" ;;
        *) echo "FAIL: after a dock the tray pixel is $AFTERDOCK_PANEL — the strip climbed back" ;;
    esac
else
    echo "FAIL: no icon docked, the stacking-after-dock case went untested"
fi
if [ "$BACK_SIZE" = "$BEFORE_SIZE" ]; then
    echo "OK: leaving fullscreen restored the exact geometry ($BACK_SIZE)"
else
    echo "FAIL: came back as «$BACK_SIZE», was «$BEFORE_SIZE»"
fi
case "$BACK_STATE" in
    *_NET_WM_STATE_FULLSCREEN*) echo "FAIL: the state is still published after leaving" ;;
    *) echo "OK: ...and the state is gone from the property" ;;
esac
if [ "$BACK_PANEL" = "$BEFORE_PANEL" ]; then
    echo "OK: ...and the panel is back on top of the desk"
else
    echo "FAIL: the panel pixel is $BACK_PANEL, was $BEFORE_PANEL before"
fi
if [ "$PREMAP" = 1 ] && [ "$PM_SIZE" = "1024x768+0+0" ]; then
    echo "OK: a window that asked BEFORE its map was framed fullscreen at once"
else
    echo "FAIL: pre-map client is «$PM_SIZE» ($PREMAP manage-time requests seen)"
fi
if [ "$XT_SIZE" = "1024x768+0+0" ]; then
    echo "OK: xterm -fullscreen came up fullscreen, by itself"
else
    echo "FAIL: xterm is «$XT_SIZE», want 1024x768+0+0"
fi
if [ "$KT_SIZE" = "1024x768+0+0" ]; then
    echo "OK: kitty --start-as fullscreen came up fullscreen, by itself"
else
    echo "FAIL: kitty is «$KT_SIZE», want 1024x768+0+0"
fi
if grep -q 'handler error' "$HERE/wm-fullscreen.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-fullscreen.log"
fi
if grep -q 'soft failure' "$HERE/wm-fullscreen.log"; then
    echo "NOTE: soft failures:"; grep 'soft failure' "$HERE/wm-fullscreen.log"
fi
