#!/bin/sh
# The ARGB frame, measured the way the ARGB tray was.
#
# A GTK4 window rounds its corners with alpha in a 32-bit visual — the
# only way it has left, GDK4 carrying no bounding-shape API — and
# counts on a compositor to blend them away. Under a reparenting
# manager the compositor is only shown the FRAME, and a frame of the
# default 24-bit visual flattens the client's alpha before it ever
# gets there: the premultiplied zeros in the corners land as literal
# black, compositor or no compositor (the owner's calculator,
# 2026-08-17). The cure under test: a chromeless frame for a 32-bit
# client is built on the client's own visual, so the alpha rides
# through and the corners show the desk.
#
# Two clients over a magenta desk with a compositor running: a GTK3
# rounded-corner window (rgba visual, undecorated — gnome-calculator's
# shape in miniature) whose corner must read as the WALLPAPER, and a
# plain 24-bit Tk client saying the same Motif word, which must keep
# the plain frame and its own opaque corner — the scoping half of the
# fix.
. "$(dirname "$0")/common.sh"
start_xvfb 800x600x24 +extension Composite +extension RENDER
trap 'kill $COMP 2>/dev/null; stop_xservers' EXIT
# The loud desk, and hsetroot rather than xsetroot: the compositor
# composites the root PIXMAP (_XROOTPMAP_ID), which xsetroot -solid
# never publishes.
hsetroot -solid '#ff00ff' 2>/dev/null
compton --backend xrender --config /dev/null \
    > "$HERE/argbframe-compositor.log" 2>&1 &
COMP=$!
sleep 1

# Pinned to opposite corners so neither window shades the other's
# probes, wherever the cascade would have put them.
rm -rf "$HERE/argbframe-config"
mkdir -p "$HERE/argbframe-config"
cat > "$HERE/argbframe-config/tk9wm.tcl" <<'EOF'
# The magenta root must be what a see-through corner shows — the
# desk's own bottom window would answer instead, in its theme color.
set-desk-window off
wm-style {filter -title argb}   {place {left top}}
wm-style {filter -title opaque} {place {right bottom}}
EOF

XDG_CONFIG_HOME="$HERE/argbframe-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-argbframe.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-argbframe.log" $WM

python3 "$HERE/argb-client-gtk.py" '#729fcf' > "$HERE/argbframe-gtk.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-argbframe.log" argb
"$LINUX/whale" "$HERE/csd-client.tcl" opaque 240x180 '#fcaf3e' 0 "" "" 30 \
    > "$HERE/argbframe-tk.log" 2>&1 &
CB=$!
wait_client "$HERE/wm-argbframe.log" opaque
sleep 2.5

import -display "$DISPLAY" -window root "$HERE/argbframe-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/argbframe-test.png"

# Each window found by its TITLE line (the renamekeep lesson), its
# frame's corner by the frame line the WM prints for it.
frame_at() {   # frame_at TITLE -> "X Y" of that client's frame
    _id=$(sed -n "s/^WM: title \(0x[0-9a-f]*\) -> «$1».*/\1/p" \
        "$HERE/wm-argbframe.log" | head -1)
    sed -n "s/^WM: frame \.f[0-9]* for $_id at +\([0-9-]*\)+\([0-9-]*\)\$/\1 \2/p" \
        "$HERE/wm-argbframe.log" | head -1
}
px() { convert "$HERE/argbframe-test.png" -format "%[pixel:p{$1,$2}]" info:; }

set -- $(frame_at argb);   AX=$1; AY=$2
set -- $(frame_at opaque); OX=$1; OY=$2
ACORNER=$(px $((AX + 4)) $((AY + 4)))
ABODY=$(px $((AX + 120)) $((AY + 90)))
OCORNER=$(px $((OX + 4)) $((OY + 4)))
OBODY=$(px $((OX + 16)) $((OY + 90)))
ARGBLINES=$(grep -c "wears the client's 32-bit visual" "$HERE/wm-argbframe.log")

kill $CA $CB 2>/dev/null
sleep 0.5
kill $WM 2>/dev/null
sleep 0.5

echo "--- argb frame at +$AX+$AY: corner=$ACORNER body=$ABODY"
echo "--- opaque frame at +$OX+$OY: corner=$OCORNER body=$OBODY"
grep -E 'WM: (frame|managed)' "$HERE/wm-argbframe.log"

echo "--- verdict"
if [ "$ARGBLINES" = 1 ]; then
    echo "OK: exactly the 32-bit client's frame took the ARGB road"
else
    echo "FAIL: $ARGBLINES frames said the 32-bit line, want exactly 1"
fi
case "$ACORNER" in
    *"255,0,255"*) echo "OK: the rounded corner shows the DESK — alpha survived the frame" ;;
    *"0,0,0"*) echo "FAIL: the corner is black — the frame flattened the alpha" ;;
    *) echo "FAIL: the corner is $ACORNER, neither the desk nor black" ;;
esac
case "$ABODY" in
    *"114,159,207"*) echo "OK: ...and the window's body is drawn where it is opaque" ;;
    *) echo "FAIL: the argb body is $ABODY, want #729fcf" ;;
esac
case "$OCORNER" in
    *"252,175,62"*) echo "OK: the 24-bit client keeps its opaque corner" ;;
    *) echo "FAIL: the 24-bit corner is $OCORNER, want #fcaf3e" ;;
esac
case "$OBODY" in
    *"252,175,62"*) echo "OK: ...and its body" ;;
    *) echo "FAIL: the 24-bit body is $OBODY, want #fcaf3e" ;;
esac
if grep -q 'handler error' "$HERE/wm-argbframe.log"; then
    echo "FAIL: handler errors present:"
    grep 'handler error' "$HERE/wm-argbframe.log"
fi
check_invariants "$HERE/wm-argbframe.log"
