#!/bin/sh
# Regression for the window-list icons, all three sources at once:
#  - client A declares a 32x32 _NET_WM_ICON (wm iconphoto) — the WM
#    must read it, downscale it and show it in the list;
#  - client B gets its icon from a config style rule (wm-style ... icon)
#    — the user's word beats whatever the client says;
#  - client C declares nothing and gets the generated pseudo-icon:
#    letters on a color badge;
#  - with the icon column in place the numbered hotkeys still pick.
. "$(dirname "$0")/common.sh"
export DISPLAY=:88
rm -f /tmp/.X88-lock /tmp/.X11-unix/X88
Xvfb :88 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

# The config carries the style-icon rule for B: a hand-drawn two-tone
# photo and a predicate by title.
rm -rf "$HERE/icon-config"
mkdir -p "$HERE/icon-config"
cat > "$HERE/icon-config/tk9wm.tcl" <<'EOF'
image create photo imgStyle -width 24 -height 24
imgStyle put #729fcf -to 0 0 24 24
imgStyle put #204a87 -to 5 5 19 19
proc is-second {w} { expr {[client-title $w] eq "второе-окно"} }
wm-style is-second {icon imgStyle}
EOF

XDG_CONFIG_HOME="$HERE/icon-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-icon.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "первое-окно" 240x120 "#8ae234" "" "" 30 "#4e9a06" &
CA=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "второе-окно" 240x120 "#fcaf3e" "" "" 30 &
CB=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "третье-окно" 240x120 "#ad7fa8" "" "" 30 &
CC=$!
sleep 1

key() { xdotool key "$@"; sleep 0.5; }

key super+t     # the static window list...
key w
key w
import -display :88 -window root "$HERE/icon-list.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/icon-list.png"
key 2           # ...still picks by the numbered hotkey (entry 2 = B)

kill $WM $CA $CB $CC 2>/dev/null

# Actors by manage order (the 0.5 s spacing makes it deterministic).
set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-icon.log")
AID=$1; BID=$2; CID=$3
echo "--- actors: A=$AID B=$BID C=$CID"
echo "--- icon lines:"
grep -E 'icon 0x|winlist open|winlist pick' "$HERE/wm-icon.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-icon.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$AID" ] || [ -z "$BID" ] || [ -z "$CID" ]; then
    echo "FAIL: missing actor ids (A=$AID B=$BID C=$CID)"
fi
if grep -q "icon $AID: _NET_WM_ICON 32x32 -> " "$HERE/wm-icon.log"; then
    echo "OK: A's _NET_WM_ICON was read and downscaled"
else
    echo "FAIL: no _NET_WM_ICON read line for A"
fi
if grep -q "winlist icon $AID: image " "$HERE/wm-icon.log"; then
    echo "OK: A's row shows the client's own icon"
else
    echo "FAIL: no image row for A"
fi
if grep -q "winlist icon $BID: image imgStyle" "$HERE/wm-icon.log"; then
    echo "OK: B's row shows the config's style icon"
else
    echo "FAIL: no imgStyle row for B"
fi
PSEUDO=$(sed -n "s/^WM: winlist icon $CID: pseudo \(.*\)$/\1/p" "$HERE/wm-icon.log")
if [ -n "$PSEUDO" ]; then
    echo "OK: C's row is the pseudo badge: $PSEUDO"
else
    echo "FAIL: no pseudo row for C"
fi
if grep -q 'winlist open (3 windows)$' "$HERE/wm-icon.log"; then
    echo "OK: the static list opened with all three"
else
    echo "FAIL: no 3-window static winlist open"
fi
PICK=$(sed -n 's/^WM: winlist pick \(0x[0-9a-f]*\)$/\1/p' "$HERE/wm-icon.log" | tail -1)
if [ "$PICK" = "$BID" ]; then
    echo "OK: hotkey 2 picked B with the icon column in place"
else
    echo "FAIL: hotkey 2 picked «$PICK», want $BID"
fi
