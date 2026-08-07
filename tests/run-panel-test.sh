#!/bin/sh
# Regression for the panel: an idempotent wmaker-style button that
# launches when its predicate finds nothing and focuses the matching
# window when it does — fired by its chord and by a mouse click — and
# the workarea carve: maximize must stop above the panel strip.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/panel-config"
mkdir -p "$HERE/panel-config"
cat > "$HERE/panel-config/tk9wm.tcl" <<'EOF'
proc is-panel-client {w} { expr {[client-title $w] eq "панель-клиент"} }
action терм {
    match is-panel-client
    launch {exec __LINUX__/whale __HERE__/client.tcl панель-клиент 240x120 #8ae234 {} {} 30 &}
}
panel-button терм
# the name is the primary key: this REFINES the action above (adds
# its chord) instead of declaring a second one — the panel must come
# up with 1 button and the chord must fire the merged action
action терм { key {<Super>z} }
EOF
sed -i "s|__LINUX__|$LINUX|; s|__HERE__|$HERE|" "$HERE/panel-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/panel-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-panel.log" 2>&1 &
WM=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.5; }

PH=$(sed -n 's/^WM: panel [^ ]* up (1 buttons, \([0-9]*\) px.*/\1/p' "$HERE/wm-panel.log" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-panel.log" | head -1)
echo "--- panel h=$PH, deco top=$TOP"

key super+z            # nothing matches -> launch
sleep 1.5              # the client comes up and is managed

"$LINUX/whale" "$HERE/client.tcl" "другое-окно" 240x120 "#fcaf3e" "" "" 30 &
CB=$!
sleep 1                # the distractor holds the focus now

key super+z            # the predicate finds the client -> focus back

# the button by MOUSE: first button sits at the panel's left edge
xdotool mousemove 25 $((600 - ${PH:-38} / 2)) click 1
import -display "$DISPLAY" -window root "$HERE/panel-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/panel-test.png"
sleep 0.5

key alt+space          # winops on the focused (panel) client...
key x                  # ...maximize: must stop above the panel
sleep 0.5
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-panel.log" | head -1)
MAXGEOM=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')

kill $WM $CB 2>/dev/null

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-panel.log")
AID=$1; BID=$2
echo "--- actors: A=$AID B=$BID"
echo "--- panel lines:"
grep -E "action терм|panel |focus ->" "$HERE/wm-panel.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-panel.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -n "$PH" ]; then
    echo "OK: the panel came up ($PH px)"
else
    echo "FAIL: no panel-up line"
fi
if grep -q 'panel default up (1 buttons' "$HERE/wm-panel.log"; then
    echo "OK: two declarations of one label merged into one button"
else
    echo "FAIL: panel-up says $(grep -o 'up ([0-9]* buttons' "$HERE/wm-panel.log" | head -1), want 1"
fi
if [ "$(grep -c "action терм: launch" "$HERE/wm-panel.log")" = 1 ]; then
    echo "OK: the empty-desk fire launched the client"
else
    echo "FAIL: want exactly one launch line"
fi
FOUND=$(grep -c "action терм: found $AID" "$HERE/wm-panel.log")
if [ "$FOUND" = 2 ]; then
    echo "OK: chord and click both found and focused A"
else
    echo "FAIL: $FOUND found-lines for A, want 2"
fi
if awk -v a="$AID" -v b="$BID" '
    /focus -> / && NF == 4 {last=$4}
    /action терм: found/ {if (last != b) exit 1; ok=1; exit}
    END {exit !ok}' "$HERE/wm-panel.log"; then
    echo "OK: the second fire found A while B held the focus"
else
    echo "FAIL: no focus handoff B -> A around the second fire"
fi
WANTMAX="788x$((600 - PH - TOP - 6))"
if [ "$MAXGEOM" = "$WANTMAX" ]; then
    echo "OK: maximize stopped above the panel ($MAXGEOM)"
else
    echo "FAIL: maximized client is $MAXGEOM, want $WANTMAX"
fi
if grep -q 'handler error' "$HERE/wm-panel.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-panel.log"
fi
