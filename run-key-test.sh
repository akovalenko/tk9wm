#!/bin/sh
# Regression for the key machinery and the window menu. Clients A then
# B are managed (B holds the focus); then:
#  - Alt+Space opens the winmenu; the initial selection is the SECOND
#    entry (the window the user is leaving is first), so a bare Enter
#    toggles to A, alt-tab style; a second Alt+Space + Enter toggles
#    back to B;
#  - the stumpwm-style sequence Super+t, w, m opens the same menu
#    through the prefix machinery (temporary keyboard grab), and Esc
#    closes it giving the focus back;
#  - Super+t followed by an unbound key aborts the sequence, and the
#    machinery still answers afterwards (a final Alt+Space + Esc).
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:78
rm -f /tmp/.X78-lock /tmp/.X11-unix/X78
Xvfb :78 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-key.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "первое-окно" 240x120+30+30 "#8ae234" &
CA=$!
sleep 0.5
"$LINUX/whale" "$HERE/client.tcl" "второе-окно" 240x120+30+30 "#fcaf3e" &
CB=$!
sleep 1

key() { xdotool key "$@"; sleep 0.5; }

key alt+space   # menu opens, selection on the previous window (A)
key Return      # picks A
key alt+space
key Return      # toggles back to B
key super+t     # prefix...
key w           # ...deeper...
key m           # ...winmenu
import -display :78 -window root "$HERE/key-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/key-test.png"
key Escape      # cancel, focus back where it was
key super+t
key q           # unbound -> abort
key alt+space   # still alive after the abort
key Escape

kill $WM $CA $CB 2>/dev/null

# Actors by manage order (the 0.5 s spacing makes it deterministic).
set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-key.log")
AID=$1; BID=$2
echo "--- actors: A=$AID B=$BID"
echo "--- key/menu/focus lines:"
grep -E 'key |winmenu|focus ->' "$HERE/wm-key.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-key.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$AID" ] || [ -z "$BID" ]; then
    echo "FAIL: missing actor ids (A=$AID B=$BID)"
fi
OPENS=$(grep -c 'winmenu open (2 windows)' "$HERE/wm-key.log")
if [ "$OPENS" = 4 ]; then
    echo "OK: winmenu opened 4 times (2x Alt+Space, sequence, post-abort)"
else
    echo "FAIL: winmenu opened $OPENS times, want 4"
fi
PICKS=$(sed -n 's/^WM: winmenu pick \(0x[0-9a-f]*\)$/\1/p' "$HERE/wm-key.log" | tr '\n' ' ')
if [ "$PICKS" = "$AID $BID " ]; then
    echo "OK: bare Enter toggled to A, then back to B (picks: $PICKS)"
else
    echo "FAIL: picks were «$PICKS», want «$AID $BID »"
fi
if grep -q 'key Super+t -> prefix' "$HERE/wm-key.log" \
        && grep -q 'key w -> prefix' "$HERE/wm-key.log" \
        && grep -q 'key m -> action' "$HERE/wm-key.log"; then
    echo "OK: the Super+t w m sequence walked prefix, prefix, action"
else
    echo "FAIL: sequence steps missing from the log"
fi
if grep -q 'key sequence abort (q unbound)' "$HERE/wm-key.log"; then
    echo "OK: an unbound key aborted the sequence"
else
    echo "FAIL: no abort line for the unbound key"
fi
# The last Alt+Space must come AFTER the abort — proof the grab state
# survived it (the log is chronological).
if awk '/key sequence abort/ {a=1} a && /winmenu open/ {ok=1} END {exit !ok}' \
        "$HERE/wm-key.log"; then
    echo "OK: the machinery still answers after the abort"
else
    echo "FAIL: no winmenu open after the abort"
fi
