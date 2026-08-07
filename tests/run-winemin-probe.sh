#!/bin/sh
# PROBE: the owner's actual subject — a WINE window through the
# iconify round trip under our WM. Ours is the only side that can
# start it here (Alt+space, the Win32 system menu's route, is our own
# winops grab and there is no unbind yet), but the interesting half is
# wine's: does its Win32 side follow WM_STATE into minimized, and does
# it come back PAINTED when WM_STATE says Normal again? That last step
# is the same mechanism `set-minimize refuse` leans on.
. "$(dirname "$0")/common.sh"
start_xvfb 900x700x24
trap 'stop_xservers; "$WINESH" server -k >/dev/null 2>&1' EXIT

key() { xdotool key "$@"; sleep 0.6; }
state() { xprop -id "$1" WM_STATE 2>/dev/null | sed -n 's/.*window state: //p'; }
mapstate() { xwininfo -id "$1" 2>/dev/null | sed -n 's/.*Map State: //p'; }

"$LINUX/whale" "$WMTCL" > "$HERE/wm-winemin.log" 2>&1 &
WM=$!
sleep 1.5
"$WINESH" server -k >/dev/null 2>&1
"$WINESH" notepad > "$HERE/winemin-client.log" 2>&1 &
sleep 6
WID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-winemin.log" | head -1)
echo "--- wine window: $WID   before: $(state "$WID") $(mapstate "$WID")"
import -window root "$HERE/winemin-before.png" 2>/dev/null

key alt+space      # our winops
key i              # ...its minimize entry
sleep 1
echo "--- after minimize: $(state "$WID") $(mapstate "$WID")"
import -window root "$HERE/winemin-iconic.png" 2>/dev/null \
    && echo "DRIVER: screenshot (iconic) -> winemin-iconic.png"

key super+t        # the static window list
key w
key w
key 1              # pick the only entry — the iconic one
sleep 2
echo "--- after restore: $(state "$WID") $(mapstate "$WID")"
import -window root "$HERE/winemin-back.png" 2>/dev/null \
    && echo "DRIVER: screenshot (restored) -> winemin-back.png"

kill $WM 2>/dev/null
"$WINESH" server -k >/dev/null 2>&1
echo "--- WM saw:"
grep -E 'iconif|winlist pick|managed|unmanage|soft failure' "$HERE/wm-winemin.log"
echo "--- wine said:"
grep -viE '^$|fixme:font|libEGL' "$HERE/winemin-client.log" | head -10
