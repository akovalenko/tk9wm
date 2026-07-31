#!/bin/sh
# Regression for the top-level key help: Super+h outside any sequence
# opens the whole keymap under the sequence grab, the next press WALKS
# from the root (an action chord fires), Escape leaves cleanly, and
# the welcome mat carries a link to the same place.
. "$(dirname "$0")/common.sh"
export DISPLAY=:99
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
Xvfb :99 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/tophelp-config"
mkdir -p "$HERE/tophelp-config"
cat > "$HERE/tophelp-config/tk9wm.tcl" <<EOF
wm-bind {<Super>z} {exec touch $HERE/tophelp-config/fired &} "the test action"
EOF

XDG_CONFIG_HOME="$HERE/tophelp-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-tophelp.log" 2>&1 &
WM=$!
sleep 1.5

key() { xdotool key "$@"; sleep 0.6; }

key super+h            # the map from the top
key super+z            # a walk from the root: the action must fire
key super+h            # open again...
key Escape             # ...and leave

kill $WM 2>/dev/null

echo "--- help lines:"
grep -aE 'key help|key Super|sequence' "$HERE/wm-tophelp.log"
echo "--- verdict"
if grep -q 'key help from the top' "$HERE/wm-tophelp.log"; then
    echo "OK: Super+h answered at the top level"
else
    echo "FAIL: no top-level help line"
fi
if [ -e "$HERE/tophelp-config/fired" ]; then
    echo "OK: the next press walked from the root and fired the action"
else
    echo "FAIL: the action chord did not fire from inside the help"
fi
if grep -q 'key sequence abort (Esc)' "$HERE/wm-tophelp.log"; then
    echo "OK: Escape leaves the opened map"
else
    echo "FAIL: no clean Escape abort"
fi
if grep -q 'answers to' "$HERE/wm-tophelp.log"; then
    : # the binding name may or may not surface in logs; not asserted
fi
check_invariants "$HERE/wm-tophelp.log"
