#!/bin/sh
# Regression for the ui host: `applet about` spawns ONE host whose
# window wears {tk9wm-about Tk9wmUi} and is managed like anybody; a
# second call finds the window instead of spawning; after the window
# closes the RUNNING host is asked (no second process); and the host
# SURVIVES a WM restart-in-place — the reopened window is found by
# match, not by memory.
. "$(dirname "$0")/common.sh"
export DISPLAY=:88
rm -f /tmp/.X88-lock /tmp/.X11-unix/X88
Xvfb :88 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/applet-config"
mkdir -p "$HERE/applet-config"
cat > "$HERE/applet-config/tk9wm.tcl" <<'EOF'
set-welcome off
panel-button dummy {launch {exec true &}}
EOF

XDG_CONFIG_HOME="$HERE/applet-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-applet.log" 2>&1 &
WM=$!
sleep 1.5

q() { printf '%s\n' "$1" > "$HERE/applet-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/applet-config/q.tcl"; }
hosts() { pgrep -fc 'ui/host.tcl' || true; }

q 'applet about' >/dev/null
sleep 3
AID=$(xdotool search --classname '^tk9wm-about$' | head -1)
ACLS=$(xprop -id "$AID" WM_CLASS 2>/dev/null | sed 's/.*= //')
H1=$(hosts)
q 'applet about' >/dev/null
sleep 1
H2=$(hosts)

# Close the applet window at the host itself (wmctrl -c speaks
# _NET_CLOSE_WINDOW, which this WM does not hear yet — a noted gap);
# the host must survive its last window.
printf 'destroy .tk9wm-about\n' > "$HERE/applet-config/qh.tcl"
"$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm-ui "$HERE/applet-config/qh.tcl" >/dev/null
sleep 1.5
q 'applet about' >/dev/null
sleep 2
H3=$(hosts)
BID=$(xdotool search --classname '^tk9wm-about$' | head -1)

# The restart is ORDERED, not called: a synchronous send whose target
# execv's mid-conversation never gets its reply (measured — the first
# version of this test hung exactly there). after 100 lets the reply
# leave first.
q 'after 100 restart-wm; list ordered' >/dev/null 2>&1
sleep 3
H4=$(hosts)
q 'applet about' >/dev/null
sleep 1

# The stale protocol: any ui file younger than the running host makes
# the next open answer "stale", the host leaves, the WM respawns — an
# edit under library/ui is one close-and-open away, no Reread involved.
printf 'destroy .tk9wm-about\n' > "$HERE/applet-config/qh.tcl"
"$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm-ui "$HERE/applet-config/qh.tcl" >/dev/null
sleep 1
touch "$ROOT/library/ui/applets/about.tcl"
q 'applet about' >/dev/null
sleep 3
H5=$(hosts)
CID=$(xdotool search --classname '^tk9wm-about$' | head -1)

kill $WM 2>/dev/null
pkill -f 'ui/host.tcl' 2>/dev/null

echo "--- applet lines:"
grep -aE 'applet|UI:' "$HERE/wm-applet.log"
echo "--- hosts: after-spawn=$H1 refind=$H2 reopen=$H3 post-restart=$H4"
echo "--- verdict"
if [ -n "$AID" ] && [ "$ACLS" = '"tk9wm-about", "Tk9wmUi"' ]; then
    echo "OK: the applet window wears {tk9wm-about Tk9wmUi}"
else
    echo "FAIL: applet window class is $ACLS"
fi
if grep -q 'applet about: spawning the ui host' "$HERE/wm-applet.log" \
        && [ "$H1" = 1 ]; then
    echo "OK: one host spawned"
else
    echo "FAIL: spawn went wrong (hosts=$H1)"
fi
if grep -q 'applet about: found' "$HERE/wm-applet.log" && [ "$H2" = 1 ]; then
    echo "OK: the second call found the window, no second host"
else
    echo "FAIL: no found-line, or hosts=$H2"
fi
if grep -q 'applet about: asked the running host' "$HERE/wm-applet.log" \
        && [ "$H3" = 1 ] && [ -n "$BID" ]; then
    echo "OK: after a close the running host reopened it — still one process"
else
    echo "FAIL: reopen path (hosts=$H3, window=$BID)"
fi
if [ "$H4" = 1 ]; then
    echo "OK: the host rode across the WM restart"
else
    echo "FAIL: hosts after restart: $H4"
fi
N=$(grep -c 'applet about: found' "$HERE/wm-applet.log")
if [ "$N" -ge 2 ]; then
    echo "OK: after the restart the window was FOUND — a match, not a memory"
else
    echo "FAIL: found-lines: $N, want 2 (one before, one after restart)"
fi
if grep -q 'UI: applet about up' "$HERE/wm-applet.log"; then
    echo "OK: the host reported the build"
else
    echo "FAIL: no build line from the host"
fi
if grep -q 'the ui world changed — respawning the host' "$HERE/wm-applet.log" \
        && grep -q 'UI: stale' "$HERE/wm-applet.log" \
        && [ "$H5" = 1 ] && [ -n "$CID" ]; then
    echo "OK: a touched ui file turned into a fresh host on the next open"
else
    echo "FAIL: stale path (hosts=$H5, window=$CID)"
fi
check_invariants "$HERE/wm-applet.log"
