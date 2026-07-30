#!/bin/sh
# Regression for WIDGETS — the desk's own furniture — on the clock,
# which is the first of them, and for the FONT HIERARCHY it is set in.
#
# The owner's requirements (2026-07-30), each one measured:
#
#  - the widget is AGNOSTIC about where it lives: the same declaration
#    with one option changed puts it on the panel, in the corner of the
#    workarea, or on the desk itself under every client window;
#  - the clock is bigger than the date, and both are DERIVED from the
#    desk font rather than stated in points — so moving the desk font
#    moves them, in proportion, with nothing else edited;
#  - widgets are CHEAP: a config reload destroys and rebuilds them, and
#    that is the whole story of how a widget changes its mind.
. "$(dirname "$0")/common.sh"
export DISPLAY=:65
rm -f /tmp/.X65-lock /tmp/.X11-unix/X65
Xvfb :65 -screen 0 900x500x24 >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
trap 'kill $XVFB 2>/dev/null; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
panel-button терминал { launch {exec xterm &} }
wm-widget clock -type clock -on {panel default} -place {right vcenter}
EOF
sleep 1

LOG="$HERE/wm-widget.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 2

widget_line() { sed -n 's/^WM: widget clock (clock) //p' "$LOG" | tail -1; }
# What the widget's own window is, from OUTSIDE: named, like every
# other piece of our furniture, so a test need not believe the log.
wid() { xdotool search --onlyvisible --name '^tk9wm-widget-clock$' | head -1; }
geom() {
    id=$(wid)
    [ -n "$id" ] || { echo "(no window)"; return; }
    xwininfo -id "$id" | awk '
        /Absolute upper-left X/ {x=$NF} /Absolute upper-left Y/ {y=$NF}
        /Width:/ {w=$2} /Height:/ {h=$2}
        END {print w "x" h "+" x "+" y}'
}
fontsize() {  # the size Tk resolved for a named font, asked of the WM
    "$LINUX/whale-cli" "$TOOLS/probe-font.tcl" :65 "$1" 2>/dev/null
}

ON_PANEL=$(geom)
FIRST=$(widget_line)
# ...sampled while the WM is alive: the workarea is a property it owns.
WAH=$(xprop -display :65 -root _NET_WORKAREA | sed 's/.*, //')
import -display :65 -window root "$HERE/widget-panel.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/widget-panel.png"

# --- the same widget, told to live somewhere else entirely
cat > "$CONF/tk9wm.tcl" <<'EOF'
panel-button терминал { launch {exec xterm &} }
wm-widget clock -type clock -on screen -place {left top} -layer desk
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" :65 >/dev/null 2>&1
sleep 1.5
ON_DESK=$(geom)
REBUILDS=$(grep -c '^WM: widget clock' "$LOG")

# --- and the fonts: a bigger desk font must carry both lines with it
BEFORE=$(grep -c '^WM: widget clock' "$LOG")
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-desk-font -size 20
wm-widget clock -type clock -on screen -place {left top} -layer desk
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" :65 >/dev/null 2>&1
sleep 1.5
BIG=$(geom)
import -display :65 -window root "$HERE/widget-desk.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/widget-desk.png"

kill $WM 2>/dev/null

echo "--- widget lines:"
grep -E '^WM: widget ' "$LOG"
echo "--- on the panel: $ON_PANEL   on the desk: $ON_DESK   with a big font: $BIG"

echo "--- verdict"
FAIL=0
if [ -n "$FIRST" ]; then
    echo "OK: the clock came up on the panel ($FIRST)"
else
    echo "FAIL: no widget line in the log"; FAIL=1
fi
# The panel is at the bottom by default; a widget riding it must sit
# inside its band, which starts below the workarea's height.
PY=$(echo "$ON_PANEL" | sed 's/.*+//')
if [ -n "$PY" ] && [ "$PY" -ge 0 ] 2>/dev/null && [ "$PY" -ge "${WAH:-0}" ]; then
    echo "OK: ...ON it — its top edge ($PY) is past where the workarea ends ($WAH)"
else
    echo "FAIL: the widget is at y=$PY, not inside the panel's band (below $WAH)"
    FAIL=1
fi
case "$ON_DESK" in
    *+0+0) echo "OK: the SAME widget, one option changed, sits at the screen's\
 top-left instead ($ON_DESK)" ;;
    *) echo "FAIL: told -on screen -place {left top} it went to $ON_DESK"; FAIL=1 ;;
esac
if [ "$REBUILDS" -ge 2 ]; then
    echo "OK: a reload rebuilt it from nothing ($REBUILDS builds logged)"
else
    echo "FAIL: only $REBUILDS build(s) — the reload did not rebuild the widget"
    FAIL=1
fi
BIGW=$(echo "$BIG" | sed 's/x.*//')
SMALLW=$(echo "$ON_DESK" | sed 's/x.*//')
if [ -n "$BIGW" ] && [ -n "$SMALLW" ] && [ "$BIGW" -gt "$SMALLW" ]; then
    echo "OK: a bigger DESK font carried the clock with it ($SMALLW -> $BIGW px\
 wide), nothing about the widget edited"
else
    echo "FAIL: the desk font grew and the clock did not ($SMALLW -> $BIGW)"
    FAIL=1
fi
if grep -q 'widget clock: build failed\|handler error' "$LOG"; then
    echo "FAIL: errors in the log:"; grep -E 'build failed|handler error' "$LOG"
    FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
