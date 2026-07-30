#!/bin/sh
# Regression for EWMH maximize: the _NET_WM_STATE maximized pair
# honored as a state action (wmctrl add/remove/toggle), as a pre-map
# request (a client that sets the property before mapping — emacs's
# `fullscreen: maximized` X resource takes this road), and published
# back while the mark holds.
. "$(dirname "$0")/common.sh"
export DISPLAY=:93
rm -f /tmp/.X93-lock /tmp/.X11-unix/X93
Xvfb :93 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/ewmhmax-config"
mkdir -p "$HERE/ewmhmax-config"
cat > "$HERE/ewmhmax-config/tk9wm.tcl" <<'EOF'
panel-button dummy {launch {exec true &}}
EOF
# a pre-map claimant: -zoomed before the first map
cat > "$HERE/ewmhmax-config/client-zoomed.tcl" <<'EOF'
package require Tk
wm title . zoomed
wm attributes . -zoomed 1
label .l -text zoomed -background #ad7fa8 -font {Sans 14}
pack .l -expand 1 -fill both
after 30000 exit
EOF

XDG_CONFIG_HOME="$HERE/ewmhmax-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-ewmhmax.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "жертва" 240x120 "#8ae234" "" "" 30 &
CA=$!
sleep 1.5
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-ewmhmax.log" | head -1)
PH=$(sed -n 's/^WM: panel [^ ]* up (1 buttons, \([0-9]*\) px.*/\1/p' "$HERE/wm-ewmhmax.log" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-ewmhmax.log" | head -1)
WANTMAX="788x$((600 - ${PH:-38} - ${TOP:-30} - 6))"

size_of() { xwininfo -id "$1" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}'; }

wmctrl -i -r "$AID" -b add,maximized_vert,maximized_horz;    sleep 1
SZ_ADD=$(size_of "$AID")
ST_ADD=$(xprop -id "$AID" _NET_WM_STATE | sed 's/.*= //')
wmctrl -i -r "$AID" -b remove,maximized_vert,maximized_horz; sleep 1
SZ_REM=$(size_of "$AID")
ST_REM=$(xprop -id "$AID" _NET_WM_STATE | sed 's/.*= //')
wmctrl -i -r "$AID" -b toggle,maximized_vert,maximized_horz; sleep 1
SZ_TOG=$(size_of "$AID")

"$LINUX/whale" "$HERE/ewmhmax-config/client-zoomed.tcl" &
CZ=$!
sleep 2
ZID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-ewmhmax.log" | sed -n 2p)
SZ_Z=$(size_of "$ZID")

kill $WM $CA $CZ 2>/dev/null

echo "--- actors: A=$AID Z=$ZID want-max=$WANTMAX"
echo "--- maximize lines:"
grep -E 'maximize|maximized' "$HERE/wm-ewmhmax.log"
echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-ewmhmax.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ "$SZ_ADD" = "$WANTMAX" ]; then
    echo "OK: add,maximized_* fit the workarea ($SZ_ADD)"
else
    echo "FAIL: after add the client is $SZ_ADD, want $WANTMAX"
fi
case $ST_ADD in
    *_NET_WM_STATE_MAXIMIZED_HORZ*_NET_WM_STATE_MAXIMIZED_VERT*)
        echo "OK: the maximized pair is published while it holds" ;;
    *) echo "FAIL: published state after add: $ST_ADD" ;;
esac
if [ "$SZ_REM" = "240x120" ]; then
    echo "OK: remove restored the asked-for size"
else
    echo "FAIL: after remove the client is $SZ_REM, want 240x120"
fi
case $ST_REM in
    *MAXIMIZED*) echo "FAIL: maximized still published after remove: $ST_REM" ;;
    *) echo "OK: the pair left the published state on remove" ;;
esac
if [ "$SZ_TOG" = "$WANTMAX" ]; then
    echo "OK: toggle maximized again ($SZ_TOG)"
else
    echo "FAIL: after toggle the client is $SZ_TOG, want $WANTMAX"
fi
if [ "$SZ_Z" = "$WANTMAX" ]; then
    echo "OK: the -zoomed client mapped maximized ($SZ_Z)"
else
    echo "FAIL: the -zoomed client is $SZ_Z, want $WANTMAX"
fi
if grep -qE 'asked to start maximized|client asks maximize on' "$HERE/wm-ewmhmax.log"; then
    echo "OK: the zoomed request was heard (whichever road Tk took)"
else
    echo "FAIL: no sign the zoomed request arrived"
fi
if grep -q 'handler error' "$HERE/wm-ewmhmax.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-ewmhmax.log"
fi
check_invariants "$HERE/wm-ewmhmax.log"
