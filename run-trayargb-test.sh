#!/bin/sh
# The ARGB tray, measured rather than argued about.
#
# With set-tray-argb on the strip becomes a 32-bit top-level and we
# advertise that visual, so a toolkit paints its icon WITH ALPHA — and
# then its see-through parts are alpha ZERO in the strip's composite
# pixmap, which a compositor shows as a HOLE straight through to the
# desk. The cure under test is the backdrop: a plain opaque top-level
# of exactly the strip's geometry, stacked directly under it, so the
# holes show the tray's own color and an antialiased edge blends
# against it.
#
# Two clients, because the failure is client-specific: Tk's own systray
# (ships in the kit) and a GTK3 GtkStatusIcon (what the world's tray
# clients actually are — Chrome's Linux status icon included). A
# compositor must run for any of this to mean anything, so one is
# started, over a magenta desk so a hole is unmistakable.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:94
rm -f /tmp/.X94-lock /tmp/.X11-unix/X94
Xvfb :94 -screen 0 800x600x24 +extension Composite +extension RENDER >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB $COMP 2>/dev/null' EXIT
sleep 1
# A LOUD desk behind the strip, so a hole through it cannot be mistaken
# for anything else. hsetroot and not xsetroot: a compositor composites
# the root PIXMAP (_XROOTPMAP_ID), which xsetroot -solid never publishes
# — see notes/xephyr-playground.md in thoughts.
hsetroot -solid '#ff00ff' 2>/dev/null
compton --backend xrender --config /dev/null >"$HERE/trayargb-compositor.log" 2>&1 &
COMP=$!
sleep 1

rm -rf "$HERE/trayargb-config"
mkdir -p "$HERE/trayargb-config"
cat > "$HERE/trayargb-config/tk9wm.tcl" <<'EOF'
set-tray-argb on
set-tray-background #2e3436
set-tray-icon-size 32
set-tray on
EOF

XDG_CONFIG_HOME="$HERE/trayargb-config" \
    "$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-trayargb.log" 2>&1 &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/tray-client.tcl" "#8ae234" > "$HERE/trayargb-tk.log" 2>&1 &
CA=$!
sleep 1.5
python3 "$HERE/tray-client-gtk.py" "#729fcf" > "$HERE/trayargb-gtk.log" 2>&1 &
CB=$!
sleep 2.5

import -display :94 -window root "$HERE/trayargb-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/trayargb-test.png"

STRIP=$(sed -n 's/^WM: tray strip \([0-9]*\)x\([0-9]*\)+\([0-9]*\)+\([0-9]*\).*(2 icons)/\1 \2 \3 \4/p' \
    "$HERE/wm-trayargb.log" | tail -1)
set -- $STRIP
SW=$1; SH=$2; SX=$3; SY=$4
px() { convert "$HERE/trayargb-test.png" -format "%[pixel:p{$1,$2}]" info:; }
# pad 3, cell 32, gap 4: cell N starts at SX+3+N*36. The corner probe
# sits inside the icon window but outside its disc; the middle probe is
# the disc itself.
BODY=$(px $((SX + 1)) $((SY + SH / 2)))
CORNER1=$(px $((SX + 5)) $((SY + 5)))
MIDDLE1=$(px $((SX + 19)) $((SY + 19)))
CORNER2=$(px $((SX + 41)) $((SY + 5)))
MIDDLE2=$(px $((SX + 55)) $((SY + 19)))
DEPTHS=$(grep -c 'depth 32' "$HERE/wm-trayargb.log")

kill $CA $CB 2>/dev/null
sleep 0.5
kill $WM 2>/dev/null
sleep 0.5

echo "--- strip ${SW}x${SH}+${SX}+${SY}, icons at depth 32: $DEPTHS"
echo "--- body=$BODY"
echo "--- tk : corner=$CORNER1 middle=$MIDDLE1"
echo "--- gtk: corner=$CORNER2 middle=$MIDDLE2"
grep -E 'WM: tray' "$HERE/wm-trayargb.log"

echo "--- verdict"
if grep -q 'visual 0x' "$HERE/wm-trayargb.log"; then
    echo "OK: the tray advertised a 32-bit visual"
else
    echo "FAIL: no ARGB visual was advertised"
fi
if [ "$DEPTHS" = 2 ]; then
    echo "OK: both clients took the offer — their icon windows are depth 32"
else
    echo "FAIL: $DEPTHS icons at depth 32, want 2"
fi
case "$BODY" in
    *"46,52,54"*) echo "OK: the strip reads as its configured color" ;;
    *) echo "FAIL: the strip body is $BODY, want #2e3436" ;;
esac
for who_px in "tk:$CORNER1" "gtk:$CORNER2"; do
    who=${who_px%%:*}; val=${who_px#*:}
    case "$val" in
        *"46,52,54"*) echo "OK: $who — the icon's transparent corner shows the tray's color" ;;
        *"0,0,0"*) echo "FAIL: $who — the corner is black, nothing blended" ;;
        *"255,0,255"*) echo "FAIL: $who — the corner is the WALLPAPER: a hole through the strip" ;;
        *) echo "FAIL: $who — the corner is $val, neither the tray nor the desk" ;;
    esac
done
case "$MIDDLE1" in
    *"138,226,52"*) echo "OK: tk — the icon itself is drawn" ;;
    *) echo "FAIL: tk — the icon's middle is $MIDDLE1, want #8ae234" ;;
esac
case "$MIDDLE2" in
    *"114,159,207"*) echo "OK: gtk — the icon itself is drawn" ;;
    *) echo "FAIL: gtk — the icon's middle is $MIDDLE2, want #729fcf" ;;
esac
if grep -q 'handler error' "$HERE/wm-trayargb.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-trayargb.log"
fi
if grep -q 'soft failure' "$HERE/wm-trayargb.log"; then
    echo "NOTE: soft failures:"; grep 'soft failure' "$HERE/wm-trayargb.log"
fi
