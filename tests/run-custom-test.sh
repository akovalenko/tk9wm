#!/bin/sh
# Regression for the customization layer: it loads after the config
# and wins, the loader names each overlapping knob (and only those),
# custom-write persists canonically and applies live, the layering
# survives a reload — and a FRESH desk (no config) shows the welcome
# note whose "hide forever" writes the first customization.
. "$(dirname "$0")/common.sh"
export DISPLAY=:96
rm -f /tmp/.X96-lock /tmp/.X11-unix/X96
Xvfb :96 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/custom-config"
mkdir -p "$HERE/custom-config"
cat > "$HERE/custom-config/tk9wm.tcl" <<'EOF'
set-title-font -weight bold
set-edge-resist 3
panel-button dummy {launch {exec true &}}
panel-button second {launch {exec true &} key {<Super>2}}
EOF
cat > "$HERE/custom-config/tk9wm.custom.tcl" <<'EOF'
set-title-font -weight normal
set-drag-slop 7
EOF

XDG_CONFIG_HOME="$HERE/custom-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-custom.log" 2>&1 &
WM=$!
sleep 1.5

q() { printf '%s\n' "$1" > "$HERE/custom-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/custom-config/q.tcl"; }

S0=$(q 'list [font actual TitleFont -weight] $::drag_slop $::edge_resist')
q reload-config >/dev/null
sleep 0.5
S1=$(q 'list [font actual TitleFont -weight] $::drag_slop $::edge_resist')
q 'custom-write {set-fade 0.33}' >/dev/null
sleep 0.5
FADE=$(q 'set ::fade')
KT=$(q 'set t [knob-table]; list [dict get $t set-fade value] [dict get $t set-minimize kind] [dict get $t set-panel-side value] [dict get $t set-title-font group]')

# COLLECTIONS: a set REPLACES by label (not adds), a remove takes the
# button and its chord away, and the file keeps the ordered
# declarations in the order they were made
q 'custom-write {panel-button-set dummy {launch {exec false &} key {<Super>9}}}' >/dev/null
q 'custom-write {panel-button-remove second}' >/dev/null
q 'custom-write {wm-bind {<Super>7} {list seven}}' >/dev/null
sleep 0.5
COLL=$(q 'set names {}
          foreach b [panel-cfg default buttons] { lappend names [lindex $b 0] }
          list buttons $names                dummykey [dict exists [lindex [lindex [panel-cfg default buttons] 0] 1] key]                secondchord [dict exists $::keymap [join [parse-chord {<Super>2}] ,]]                newchord [dict exists $::keymap [join [parse-chord {<Super>9}] ,]]')
FILEORDER=$(grep -n 'panel-button\|wm-bind\|set-fade' "$HERE/custom-config/tk9wm.custom.tcl" | tr '
' ' ')

kill $WM 2>/dev/null
sleep 0.5

echo "--- phase 2: a fresh desk, no config at all"
rm -rf "$HERE/custom-fresh"
mkdir -p "$HERE/custom-fresh"
XDG_CONFIG_HOME="$HERE/custom-fresh" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-fresh.log" 2>&1 &
WM2=$!
sleep 1.5
qf() { printf '%s\n' "$1" > "$HERE/custom-fresh/q.tcl"
       "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/custom-fresh/q.tcl"; }
WELCOME=$(qf 'dict exists $::widgets __welcome')
qf welcome-hide >/dev/null
sleep 0.5
AFTERHIDE=$(qf 'list $::welcome [dict exists $::widgets __welcome]')
kill $WM2 2>/dev/null

echo "--- states: start={$S0} reload={$S1} fade=$FADE welcome=$WELCOME afterhide={$AFTERHIDE}"
echo "--- layer lines:"
grep -aE 'custom|welcome' "$HERE/wm-custom.log" "$HERE/wm-fresh.log" | grep -v widget
echo "--- verdict"
if [ "$S0" = "normal 7 3" ]; then
    echo "OK: the click wins, the untouched knobs hold (normal 7 3)"
else
    echo "FAIL: start state is {$S0}, want {normal 7 3}"
fi
if [ "$S1" = "normal 7 3" ]; then
    echo "OK: the layering survives a reload"
else
    echo "FAIL: after reload {$S1}"
fi
N=$(grep -c 'custom overrides the config: set-title-font' "$HERE/wm-custom.log")
if [ "$N" -ge 2 ]; then
    echo "OK: the overlap is named, on load and on reload"
else
    echo "FAIL: $N overlap lines for set-title-font"
fi
if grep -q 'overrides the config: set-drag-slop' "$HERE/wm-custom.log"; then
    echo "FAIL: a knob only custom touched was reported as an overlap"
else
    echo "OK: no false overlap for set-drag-slop"
fi
if [ "$FADE" = 0.33 ] && grep -q 'set-fade 0.33' "$HERE/custom-config/tk9wm.custom.tcl"; then
    echo "OK: custom-write applied live and persisted canonically"
else
    echo "FAIL: fade=$FADE, file: $(grep set-fade "$HERE/custom-config/tk9wm.custom.tcl")"
fi
if grep -q 'MACHINE-WRITTEN' "$HERE/custom-config/tk9wm.custom.tcl" \
        && grep -q 'set-title-font -weight normal' "$HERE/custom-config/tk9wm.custom.tcl"; then
    echo "OK: the rewrite kept the header and the standing entries"
else
    echo "FAIL: the rewritten custom file lost its shape"
fi
if [ "$KT" = "0.33 {choice iconify refuse} bottom fonts" ]; then
    echo "OK: knob-table serves kinds, groups and live values"
else
    echo "FAIL: knob-table sample is {$KT}"
fi
if [ "$WELCOME" = 1 ]; then
    echo "OK: a fresh desk lays out the welcome mat"
else
    echo "FAIL: no welcome widget on the fresh desk"
fi
if [ "$AFTERHIDE" = "off 0" ] \
        && grep -q 'set-welcome off' "$HERE/custom-fresh/tk9wm.custom.tcl"; then
    echo "OK: hide-forever wrote the first customization and took the mat away"
else
    echo "FAIL: after hide {$AFTERHIDE}, file: $(cat "$HERE/custom-fresh/tk9wm.custom.tcl" 2>/dev/null | tail -1)"
fi
echo "--- collections: $COLL"
echo "--- file: $FILEORDER"
case $COLL in
    "buttons dummy dummykey 1 secondchord 0 newchord 1")
        echo "OK: set replaced by label, remove took the button and its chord" ;;
    *) echo "FAIL: collections: $COLL" ;;
esac
case $FILEORDER in
    *set-fade*wm-bind*panel-button*)
        echo "OK: the file sorts the knobs and binds, then keeps declaration order" ;;
    *) echo "FAIL: file layout: $FILEORDER" ;;
esac
check_invariants "$HERE/wm-custom.log"
check_invariants "$HERE/wm-fresh.log"
