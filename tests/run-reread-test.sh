#!/bin/sh
# Regression for Reread vs config state: a Reread replaces PROCS and
# must not touch what the config wrote — the title font's boldness
# (font_kin is config state; the stock declarations used to overwrite
# it on every re-source: bold after Reload, plain after Reread, a
# pattern the owner could not pin) and a default chord the config
# rebound (the keymap is config state too; a bare top-level
# policy-default-bindings used to re-floor it). Reload must keep both
# too — there the config speaks again on the clean floor.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/reread-config"
mkdir -p "$HERE/reread-config"
cat > "$HERE/reread-config/tk9wm.tcl" <<EOF
set-title-font -weight bold
action dummy {launch {exec true &}}
panel-button dummy
wm-bind {<Alt>space} {exec touch $HERE/reread-config/rebound-fired &}
EOF

XDG_CONFIG_HOME="$HERE/reread-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-reread.log" 2>&1 &
WM=$!
sleep 1.5

cat > "$HERE/reread-config/q-weight.tcl" <<'EOF'
font actual TitleFont -weight
EOF
cat > "$HERE/reread-config/q-reread.tcl" <<'EOF'
Reread
EOF
cat > "$HERE/reread-config/q-reload.tcl" <<'EOF'
reload-config
EOF
ask() { "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$1"; }

W0=$(ask "$HERE/reread-config/q-weight.tcl")
ask "$HERE/reread-config/q-reread.tcl" >/dev/null
sleep 0.5
W1=$(ask "$HERE/reread-config/q-weight.tcl")
ask "$HERE/reread-config/q-reload.tcl" >/dev/null
sleep 0.5
W2=$(ask "$HERE/reread-config/q-weight.tcl")
ask "$HERE/reread-config/q-reread.tcl" >/dev/null
sleep 0.5
W3=$(ask "$HERE/reread-config/q-weight.tcl")

# treesync's maps are STATE and must ride a Reread like the rest: a
# re-source that wiped them made the next same-signature build MAKE
# every row again beside the survivors — two of every button on the
# owner's strip (2026-07-31), after exactly this alternation
cat > "$HERE/reread-config/q-strip.tcl" <<'EOF'
set T [panel-window default].t
list items [llength [$T item children 0]] \
     shown [llength [panel-cfg default shown]]
EOF
STRIP=$(ask "$HERE/reread-config/q-strip.tcl")

rm -f "$HERE/reread-config/rebound-fired"
xdotool key alt+space
sleep 1
xdotool key Escape      # closes the winops menu if the rebind was lost

kill $WM 2>/dev/null

echo "--- weights: start=$W0 reread=$W1 reload=$W2 reread=$W3"
echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-reread.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ "$W0" = bold ]; then
    echo "OK: the config's bold took"
else
    echo "FAIL: start weight is $W0"
fi
if [ "$W1" = bold ]; then
    echo "OK: Reread left the title font alone"
else
    echo "FAIL: Reread turned the title font $W1"
fi
if [ "$W2" = bold ] && [ "$W3" = bold ]; then
    echo "OK: bold survives the whole Reload/Reread alternation"
else
    echo "FAIL: alternation gave reload=$W2 reread=$W3"
fi
if [ -e "$HERE/reread-config/rebound-fired" ]; then
    echo "OK: the config's rebind of a default chord survived Reread"
else
    echo "FAIL: alt+space fell back to the default after Reread"
fi
case $STRIP in
    "items 1 shown 1")
        echo "OK: the strip holds one item per button through the alternation" ;;
    *) echo "FAIL: strip after the alternation: $STRIP" ;;
esac
check_invariants "$HERE/wm-reread.log"
