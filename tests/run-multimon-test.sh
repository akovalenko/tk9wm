#!/bin/sh
# Multihead: the workarea goes per monitor. Two legs, one per source.
#
# RANDR leg — an Xvfb split in two by `xrandr --setmonitor` (RandR 1.5
# user monitors, the same thing a real desk's xrandr does). The server
# runs -noreset, and that is load-bearing, not hygiene: user monitors
# are CLIENT state, and a server whose last client left resets and
# forgets them — every xrandr invocation here is such a client until
# the WM comes up and holds the connection (measured, 2026-08-04).
#
# XINERAMA leg — a nested Xephyr with two -screen and +xinerama, the
# one fake multihead a headless test can raise. Its RandR answers
# GetMonitors with a single monitor the size of the FIRST screen (it
# lies), its Xinerama tells the truth — so this leg proves the
# fallback picks the truthful source: the panel would be 700 wide on
# a desk whose bounding box is 1200.
#
# What both legs check: the panel spans its PRIMARY MONITOR, not the
# bounding box; a window claimed onto the second monitor maximizes to
# THAT monitor's workarea and fullscreens to its whole glass — and on
# the xinerama leg the second head is SHORTER than the root, so a
# maximize that reached the bounding box's bottom would hang 100 px
# into the dead zone nobody can see.
. "$(dirname "$0")/common.sh"
for n in 78 79 80; do rm -f /tmp/.X$n-lock /tmp/.X11-unix/X$n; done

rm -rf "$HERE/multimon-config"
mkdir -p "$HERE/multimon-config"
cat > "$HERE/multimon-config/tk9wm.tcl" <<'EOF'
proc never {w} { return 0 }
action тест {match never}
panel-button тест
EOF

fail=0
frame() {  # display client-id -> the FRAME's rect, per the randr test
    DISPLAY=$1 xwininfo -id "$2" | awk -v b="$BW" -v t="$TOP" '
        /Width:/ {w=$2} /Height:/ {h=$2}
        /Absolute upper-left X/ {x=$NF} /Absolute upper-left Y/ {y=$NF}
        END {print (w + 2*b) "x" (h + t + b) "+" (x - b) "+" (y - t)}'
}
client() {  # display client-id -> the CLIENT's own rect
    DISPLAY=$1 xwininfo -id "$2" | awk '
        /Width:/ {w=$2} /Height:/ {h=$2}
        /Absolute upper-left X/ {x=$NF} /Absolute upper-left Y/ {y=$NF}
        END {print w "x" h "+" x "+" y}'
}
chrome() {  # wm-log -> BW/TOP for frame()
    eval "$(sed -n 's/^WM: titlebar h=\([0-9]*\) top=\([0-9]*\).*/TITLEH=\1; TOP=\2/p' \
            "$1" | head -1)"
    BW=$((TOP - TITLEH - 2))
}
ok()  { echo "OK: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# ---------------- leg 1: RandR user monitors on Xvfb ----------------
Xvfb :78 -screen 0 1000x700x24 -noreset >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB $XVFB2 $XEPHYR 2>/dev/null' EXIT
sleep 1
xrandr -d :78 --setmonitor left  600/160x700/180+0+0   screen >/dev/null 2>&1
xrandr -d :78 --setmonitor right 400/110x700/180+600+0 none   >/dev/null 2>&1

DISPLAY=:78 XDG_CONFIG_HOME="$HERE/multimon-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-multimon.log" 2>&1 &
WM=$!
sleep 1.5

DISPLAY=:78 "$LINUX/whale" "$HERE/client.tcl" "левый" "" "#8ae234" "" "" 30 &
CA=$!
sleep 1
DISPLAY=:78 "$LINUX/whale" "$HERE/client.tcl" "правый" 240x120+700+50 "#fcaf3e" "" "" 30 &
CB=$!
sleep 1

chrome "$HERE/wm-multimon.log"
# Client ids from the WM's own log, IN START ORDER — xdotool's --name
# does not survive a C locale meeting a Cyrillic title, and xwininfo
# handed an empty -id waits for a CLICK, forever, headless.
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-multimon.log" | sed -n 1p)
BID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-multimon.log" | sed -n 2p)
if [ -z "$AID" ] || [ -z "$BID" ]; then
    bad "the WM did not manage both clients (A=«$AID» B=«$BID»)"
    exit 1
fi
PH=$(sed -n 's/^WM: panel [^ ]* up (1 buttons, \([0-9]*\) px.*/\1/p' \
     "$HERE/wm-multimon.log" | head -1)

if grep -q "panel default up (1 buttons, $PH px, bottom/row, 600x${PH}+0+$((700 - PH)))" \
        "$HERE/wm-multimon.log"; then
    ok "the panel spans its 600-wide primary monitor, not the 1000 box"
else
    bad "no primary-wide panel line (expected 600x${PH}+0+$((700 - PH)))"
    grep 'panel .* up' "$HERE/wm-multimon.log" | sed 's/^/    /'
fi

WA=$(DISPLAY=:78 xprop -root _NET_WORKAREA | sed 's/.*= //; s/,//g' \
     | awk '{print $3 "x" $4 "+" $1 "+" $2}')
if [ "$WA" = "1000x$((700 - PH))+0+0" ]; then
    ok "_NET_WORKAREA keeps the one-rect convention (whole screen minus strip: $WA)"
else
    bad "_NET_WORKAREA is $WA, wanted 1000x$((700 - PH))+0+0"
fi

AF=$(frame :78 "$AID")
# right edge of the frame = width + x, both dug out of WxH+X+Y
ARIGHT=$(( $(echo "$AF" | sed 's/x.*//') + $(echo "$AF" | sed 's/.*+\(-*[0-9]*\)+.*/\1/') ))
if [ "$ARIGHT" -le 600 ]; then
    ok "the unclaimed client cascaded onto the primary monitor ($AF)"
else
    bad "the unclaimed client leaked off the primary ($AF)"
fi

BF=$(frame :78 "$BID")
case $BF in
    *+7[0-9][0-9]+*) ok "the +700+50 claim landed on the right monitor ($BF)" ;;
    *) bad "the claim did not land at x=7xx ($BF)" ;;
esac

DISPLAY=:78 wmctrl -i -r "$BID" -b add,maximized_vert,maximized_horz
sleep 1
BM=$(frame :78 "$BID")
if [ "$BM" = "400x700+600+0" ]; then
    ok "maximize filled the RIGHT monitor's workarea ($BM)"
else
    bad "maximize gave $BM, wanted 400x700+600+0"
fi
DISPLAY=:78 wmctrl -i -r "$BID" -b remove,maximized_vert,maximized_horz
sleep 1

DISPLAY=:78 wmctrl -i -r "$BID" -b add,fullscreen
sleep 1
BC=$(client :78 "$BID")
if [ "$BC" = "400x700+600+0" ]; then
    ok "fullscreen covered the right monitor's whole glass ($BC)"
else
    bad "fullscreen client is $BC, wanted 400x700+600+0"
fi
DISPLAY=:78 wmctrl -i -r "$BID" -b remove,fullscreen
sleep 1

DISPLAY=:78 import -window root "$HERE/multimon-randr.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/multimon-randr.png"
check_invariants "$HERE/wm-multimon.log"
kill $WM $CA $CB 2>/dev/null

# ---------------- leg 2: Xinerama truth inside Xephyr ----------------
Xvfb :79 -screen 0 1300x600x24 >/dev/null 2>&1 &
XVFB2=$!
sleep 1
DISPLAY=:79 Xephyr :80 -screen 700x500 -screen 500x400 +xinerama >/dev/null 2>&1 &
XEPHYR=$!
sleep 1.5

DISPLAY=:80 XDG_CONFIG_HOME="$HERE/multimon-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-multimon-xin.log" 2>&1 &
WM2=$!
sleep 1.5

DISPLAY=:80 "$LINUX/whale" "$HERE/client.tcl" "второй" 240x120+800+50 "#729fcf" "" "" 30 &
CC=$!
sleep 1

chrome "$HERE/wm-multimon-xin.log"
CID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-multimon-xin.log" | sed -n 1p)
if [ -z "$CID" ]; then
    bad "the WM did not manage the xinerama-leg client"
    exit 1
fi
PH=$(sed -n 's/^WM: panel [^ ]* up (1 buttons, \([0-9]*\) px.*/\1/p' \
     "$HERE/wm-multimon-xin.log" | head -1)

if grep -q "panel default up (1 buttons, $PH px, bottom/row, 700x${PH}+0+$((500 - PH)))" \
        "$HERE/wm-multimon-xin.log"; then
    ok "the xinerama leg took the truthful source: the panel is 700 wide on a 1200 box"
else
    bad "no 700-wide panel line — did GetMonitors' lie win?"
    grep 'panel .* up' "$HERE/wm-multimon-xin.log" | sed 's/^/    /'
fi

DISPLAY=:80 wmctrl -i -r "$CID" -b add,maximized_vert,maximized_horz
sleep 1
CM=$(frame :80 "$CID")
if [ "$CM" = "500x400+700+0" ]; then
    ok "maximize on the short head stopped at ITS bottom — not 100 px into the dead zone ($CM)"
else
    bad "maximize on the short head gave $CM, wanted 500x400+700+0"
fi

DISPLAY=:80 import -window root "$HERE/multimon-xinerama.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/multimon-xinerama.png"
check_invariants "$HERE/wm-multimon-xin.log"
kill $WM2 $CC 2>/dev/null

[ "$fail" = 0 ] && echo "OK: multimon suite ran to completion" \
                || echo "FAIL: multimon suite had failures"
