#!/bin/sh
# Regression for the config reload: no restart, no client disturbed.
#
# The contract under test is "everything configurable goes back to the
# CODE's defaults, and the config then draws on that clean floor". So
# the run goes through three configs on one live WM — a rich one, a
# DIFFERENT one, and an empty one — and after each it measures what a
# client of the desk would see. The empty pass is the important one: it
# proves the previous config left nothing behind.
. "$(dirname "$0")/common.sh"
start_xvfb

CONF="$HERE/reload-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-panel-side right
action один {}
action два {}
panel-button один
panel-button два
set-tray on
wm-bind {<Super>F1} {puts "WM: CHORD ONE"}
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-reload.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-reload.log" $WM

# a client and a tray icon, both of which must survive every reload
"$LINUX/whale" "$HERE/client.tcl" "живучий" 240x120 "#8ae234" "" "" 60 \
    > "$HERE/reload-client.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-reload.log" 'живучий'
"$LINUX/whale" "$HERE/tray-client.tcl" "#729fcf" > "$HERE/reload-tray.log" 2>&1 &
CB=$!
sleep 1.5

CID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-reload.log" | head -1)
ICON=$(sed -n 's/^WM: tray: docked \(0x[0-9a-f]*\) in slot .*/\1/p' "$HERE/wm-reload.log" | head -1)
# "panel NAME up (N buttons, H px, SIDE/PRESET, geometry)" — the count and
# the SIDE are what the two configs differ in, and the side is the
# telling one: it is a knob the second config never mentions, so it can
# only be right if the reset put it back.
panel() { sed -n 's/^WM: panel [^ ]* up (\([0-9]*\) buttons, [0-9]* px, \([a-z]*\)\/.*/\1 \2/p' "$HERE/wm-reload.log" | tail -1; }
work() { xprop -root _NET_WORKAREA 2>/dev/null | sed 's/.*= //'; }
icon_parent() { xwininfo -id "$1" -children 2>/dev/null | sed -n 's/^  Parent window id: \(0x[0-9a-f]*\).*/\1/p'; }

P1=$(panel); W1=$(work)
xdotool key super+F1; sleep 0.5
CH1=$(grep -c 'CHORD ONE' "$HERE/wm-reload.log")

# --- pass 2: a DIFFERENT config, reloaded in place
cat > "$CONF/tk9wm.tcl" <<'EOF'
action единственный {}
panel-button единственный
set-tray on
wm-bind {<Super>F2} {puts "WM: CHORD TWO"}
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY"
sleep 2
P2=$(panel); W2=$(work)
ICON_P2=$(icon_parent "$ICON")
xdotool key super+F1; sleep 0.4
xdotool key super+F2; sleep 0.4
CH1_AFTER=$(grep -c 'CHORD ONE' "$HERE/wm-reload.log")
CH2=$(grep -c 'CHORD TWO' "$HERE/wm-reload.log")

# --- pass 3: an EMPTY config — the desk must fall back to stock
: > "$CONF/tk9wm.tcl"
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY"
sleep 2
PANEL3=$(xwininfo -root -children 2>/dev/null | grep -c '"panel"')
TRAY3=$(xwininfo -root -children 2>/dev/null | grep -c '"tray"')
W3=$(work)
ICON_P3=$(icon_parent "$ICON")
ROOTID=$(xwininfo -root 2>/dev/null | sed -n 's/^xwininfo: Window id: \(0x[0-9a-f]*\).*/\1/p')
JUST3=$(grep -c 'WM: config applied' "$HERE/wm-reload.log")
CLIENT_ALIVE=$(xwininfo -id "$CID" 2>/dev/null | grep -c "Map State: IsViewable")

kill $CA $CB 2>/dev/null
sleep 0.5
kill $WM 2>/dev/null
sleep 0.5

echo "--- pass1 panel «$P1» workarea «$W1»; pass2 panel «$P2» workarea «$W2»"
echo "--- pass3 panel windows=$PANEL3 tray windows=$TRAY3 workarea «$W3»"
echo "--- client $CID viewable=$CLIENT_ALIVE, icon $ICON parent after reload=$ICON_P2"
grep -E 'config reload|config applied|key bindings cleared|config .* FAILED' "$HERE/wm-reload.log"

echo "--- verdict"
if [ "$P1" = "2 right" ]; then
    echo "OK: the first config built its panel (2 buttons, on the right edge)"
else
    echo "FAIL: pass1 panel «$P1», want «2 right»"
fi
if [ "$CH1" = 1 ]; then
    echo "OK: its chord fired"
else
    echo "FAIL: Super+F1 fired $CH1 times in pass 1"
fi
if [ "$P2" = "1 bottom" ]; then
    echo "OK: the reload rebuilt the panel from the NEW config, on the DEFAULT edge"
else
    echo "FAIL: pass2 panel «$P2», want «1 bottom» (the side must be back to default)"
fi
if [ "$CH1_AFTER" = "$CH1" ] && [ "$CH2" = 1 ]; then
    echo "OK: the old chord is gone and the new one works"
else
    echo "FAIL: old chord fired $CH1_AFTER (was $CH1), new chord $CH2"
fi
if [ "$ICON_P2" = "$(sed -n 's/^WM: tray: docked 0x[0-9a-f]* in slot \(0x[0-9a-f]*\).*/\1/p' "$HERE/wm-reload.log" | tail -1)" ]; then
    echo "OK: the tray icon came back into a cell of the reloaded tray"
else
    echo "FAIL: after the reload the icon's parent is «$ICON_P2»"
fi
if [ "$PANEL3" = 0 ] && [ "$TRAY3" = 0 ]; then
    echo "OK: an empty config leaves no panel and no tray"
else
    echo "FAIL: empty config left panel=$PANEL3 tray=$TRAY3 windows"
fi
if [ "$ICON_P3" = "$ROOTID" ]; then
    echo "OK: ...and the icon was handed back to the root, not destroyed"
else
    echo "FAIL: after the tray went away the icon's parent is «$ICON_P3»"
fi
if [ "$W3" = "0, 0, 800, 600" ]; then
    echo "OK: ...and the workarea is the whole screen again ($W3)"
else
    echo "FAIL: workarea after the empty config «$W3», want the full screen"
fi
if [ "$CLIENT_ALIVE" = 1 ]; then
    echo "OK: the client lived through all three configs untouched"
else
    echo "FAIL: the client did not survive the reloads"
fi
if [ "$JUST3" = 2 ]; then
    echo "OK: exactly two reloads were applied"
else
    echo "FAIL: $JUST3 «config applied» lines, want 2"
fi
# from the first reload on: pass 2 rebuilds its one panel once, pass 3
# (empty config) builds nothing — a build per config SENTENCE would
# push this past one (the startup is exempt: its widget pass may
# honestly rebuild once more when the widgets' thickness first lands)
BUILDS=$(sed -n '/config reload requested/,$p' "$HERE/wm-reload.log" | grep -c 'panel .* up (')
if [ "$BUILDS" -le 1 ]; then
    echo "OK: the reloads rebuilt the strips once in total ($BUILDS), not once per config sentence"
else
    echo "FAIL: $BUILDS strip builds across two reloads — the hold leaks"
fi
if grep -q 'handler error' "$HERE/wm-reload.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-reload.log"
fi
if grep -q 'soft failure' "$HERE/wm-reload.log"; then
    echo "NOTE: soft failures:"; grep 'soft failure' "$HERE/wm-reload.log"
fi
