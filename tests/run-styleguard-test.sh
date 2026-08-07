#!/bin/sh
# Regression for the wm-style declaration guard: a rule whose settings
# are not a dict (place max force — three words) must fail AT ITS OWN
# CONFIG LINE, loudly, and never enter the rule list — the desk stays
# alive, windows manage, the winlist opens. The alternative was
# measured on the owner's desk: the rule detonates inside style-of on
# every matching window, and alt-tab becomes an empty 200x200 husk.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/styleguard-config"
mkdir -p "$HERE/styleguard-config"
cat > "$HERE/styleguard-config/tk9wm.tcl" <<'EOF'
action dummy {launch {exec true &}}
panel-button dummy
wm-style always {place max force}
EOF

XDG_CONFIG_HOME="$HERE/styleguard-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-styleguard.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-styleguard.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "жертва" 240x120 "#8ae234" "" "" 30 &
CA=$!
sleep 1.5
xdotool key alt+Tab
sleep 1
xdotool key Escape
sleep 0.5

kill $WM $CA 2>/dev/null

echo "--- log:"
grep -aE "FAILED|winlist|managed|key action error" "$HERE/wm-styleguard.log"
echo "--- verdict"
if grep -q 'FAILED: wm-style: settings is not a dict' "$HERE/wm-styleguard.log"; then
    echo "OK: the config died at its own line, and said which"
else
    echo "FAIL: no declaration-time error for the malformed rule"
fi
if grep -q 'styleguard-config/tk9wm.tcl" line 3' "$HERE/wm-styleguard.log"; then
    echo "OK: ...and the log names the file and the LINE of the corpse"
else
    echo "FAIL: no file-and-line blame in the log"
fi
if grep -q 'managed 0x' "$HERE/wm-styleguard.log"; then
    echo "OK: the desk still manages windows"
else
    echo "FAIL: nothing got managed after the bad config"
fi
if grep -q 'winlist open' "$HERE/wm-styleguard.log"; then
    echo "OK: the window list opens"
else
    echo "FAIL: no winlist-open line"
fi
if grep -q 'key action error' "$HERE/wm-styleguard.log"; then
    echo "FAIL: the rule still detonated at use"
else
    echo "OK: nothing detonated later"
fi
check_invariants "$HERE/wm-styleguard.log"
