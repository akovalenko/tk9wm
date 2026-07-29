#!/bin/sh
# PROBE: does a wine window still take the keyboard after the iconify
# round trip? (Owner's report: whale.exe/smsrc — and notepad on his
# desk — go keyboard-dead after minimize+restore, whichever side
# started the minimize.) Typing is the only honest measure, so the
# evidence is what ends up in notepad's buffer, in the screenshots.
#
# A SECOND window (an xterm) shares the desk on purpose: with only one
# window the focus parks on the holder while the victim is iconic and
# comes back to an empty desk; with two, restoring has to TAKE the
# focus from a live client — and wine's focus-stealing guard judges our
# invitation against _NET_ACTIVE_WINDOW, which then points at the
# neighbour. That is the difference between a desk and a test tube.
. "$(dirname "$0")/common.sh"
LOG="$HERE/wm-winefocus.log"
export DISPLAY=:91
rm -f /tmp/.X91-lock /tmp/.X11-unix/X91
Xvfb :91 -screen 0 900x700x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null; "$WINESH" server -k >/dev/null 2>&1' EXIT
sleep 1

key() { xdotool key "$@"; sleep 0.6; }
focusnow() {
    printf 'X focus=%s  _NET_ACTIVE=%s' \
        "$(xdotool getwindowfocus 2>/dev/null)" \
        "$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | sed 's/.*# //')"
}
# The window list numbers its entries in MRU order, which shifts under
# us — so the hotkey is derived from the log the list itself writes.
open_list_and_pick() {   # $1 = window id to pick
    MARK=$(wc -l < "$LOG")
    key super+t; key w; key w
    N=$(sed -n "$((MARK + 1)),\$p" "$LOG" | sed -n 's/^WM: winlist icon \(0x[0-9a-f]*\).*/\1/p' \
        | grep -n "^$1\$" | cut -d: -f1)
    if [ -z "$N" ]; then echo "    (victim not in the list — aborting pick)"; key Escape; return 1; fi
    echo "    picking entry $N"
    key "$N"
}

"$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5
"$WINESH" server -k >/dev/null 2>&1
WINEDEBUG="${WINEDEBUG:-}" "$WINESH" notepad > "$HERE/winefocus-client.log" 2>&1 &
sleep 6
WID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | head -1)
xterm -T сосед -e sleep 120 &
sleep 3
xdotool windowactivate "$((WID))" 2>/dev/null
xdotool mousemove 300 200 click 1     # click the wine window back into focus
sleep 2
echo "--- wine window: $WID    neighbour: an xterm"

echo "--- before:    $(focusnow)"
xdotool type --delay 60 'BEFORE'
sleep 1
import -window root "$HERE/winefocus-1-before.png" 2>/dev/null

key alt+space; key i          # our winops -> minimize
sleep 1
echo "--- iconic:    $(focusnow)"

open_list_and_pick "$WID"
sleep 2
echo "--- restored:  $(focusnow)"
xdotool type --delay 60 'AFTER'
sleep 1
import -window root "$HERE/winefocus-2-after.png" 2>/dev/null \
    && echo "DRIVER: screenshots -> winefocus-1-before.png / winefocus-2-after.png"

# and a click, the usual human repair: does THAT bring the keyboard back?
xdotool mousemove 300 200 click 1
sleep 1
echo "--- after click: $(focusnow)"
xdotool type --delay 60 'CLICKED'
sleep 1
import -window root "$HERE/winefocus-3-clicked.png" 2>/dev/null

kill $WM 2>/dev/null
"$WINESH" server -k >/dev/null 2>&1
echo "--- WM saw:"
grep -E 'iconif|focus ->|invit|winlist pick|soft failure|REFUSED' "$LOG"
