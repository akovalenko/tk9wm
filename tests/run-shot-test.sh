#!/bin/sh
# Regression for Window-Shot — the window read off the screen, frame
# and all, into a PNG nothing external helped with.
#
# Two clients share one spot: red A covers blue B. Shooting the
# focused A must yield A's own pixels — the client body red at the
# frame's client offset, the titlebar wearing the focus blue above
# it. Shooting B by id must RAISE it first and settle, so the same
# probe points answer B's blue under an UNFOCUSED grey bar (the shot
# raises, it does not focus). The PNG is loaded back in the WM's own
# Tk and probed by pixel; its size must be the one the log declared.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1.5; }
LOG="$HERE/wm-shot.log"
CONF="$HERE/shot-config"
ask() {
    printf '%s\n' "$1" > "$CONF/ask.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/ask.tcl" 2>&1
}

rm -rf "$CONF" /tmp/tk9wm-shot-dir; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
wm-bind {<Super>1} {puts "TEST: shotA <[Window-Shot 0 /tmp/tk9wm-shot-dir]>"}
proc Shot-B {} {
    set b [lindex [panel-matches шотБ {match {filter -title "шотБ*"}}] 0]
    puts "TEST: shotB <[Window-Shot $b /tmp/tk9wm-shot-dir]>"
}
wm-bind {<Super>2} Shot-B
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

"$LINUX/whale" "$HERE/client.tcl" "шотБ-окно" 240x120+100+100 "#204a87" "" "" 90 \
    > "$HERE/shot-b.log" 2>&1 &
CB=$!
wait_client "$LOG" 'шотБ-окно'
"$LINUX/whale" "$HERE/client.tcl" "шотА-окно" 240x120+100+100 "#cc0000" "" "" 90 \
    > "$HERE/shot-a.log" 2>&1 &
CA=$!
wait_client "$LOG" 'шотА-окно'

key super+1
key super+2
sleep 1

kill $WM $CA $CB 2>/dev/null

SHOTA=$(sed -n 's/^TEST: shotA <\(.*\)>$/\1/p' "$LOG" | head -1)
SHOTB=$(sed -n 's/^TEST: shotB <\(.*\)>$/\1/p' "$LOG" | head -1)
GEOA=$(sed -n 's/^WM: Window-Shot 0x[0-9a-f]* -> .* (\([0-9x]*\))$/\1/p' "$LOG" | sed -n 1p)
echo "--- A: $SHOTA ($GEOA)"
echo "--- B: $SHOTB"

# probed OFFLINE: a fresh Tk (whale-cli has none — use the batteries'
# host, a bare whale on this same display is gone with the WM), so
# decode in a throwaway whale on a fresh Xvfb-less... simplest honest:
# the WM is gone, probe with a one-shot whale script under this Xvfb.
probe() {
    cat > "$CONF/probe.tcl" <<PEOF
package require Tk
wm withdraw .
image create photo sh -file {$1}
puts "[image width sh] [image height sh] | [sh get $2 $3]"
exit 0
PEOF
    "$LINUX/whale" "$CONF/probe.tcl" 2>/dev/null | tail -1
}
# the client is a label with its TITLE centered on the colour, so the
# body is probed near the client area's corner, clear of the glyphs
APX=$(probe "$SHOTA" 18 46)
ABAR=$(probe "$SHOTA" 126 15)
BPX=$(probe "$SHOTB" 18 46)
BBAR=$(probe "$SHOTB" 126 15)
echo "--- A body: $APX  bar: $ABAR"
echo "--- B body: $BPX  bar: $BBAR"

echo "--- verdict"
BAD=0
if grep -q 'soft failure\|handler error' "$LOG"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$LOG"; BAD=1
fi
if [ -n "$SHOTA" ] && [ -f "$SHOTA" ]; then
    echo "OK: the shot answered a path and the file is there"
else
    echo "FAIL: no shot file (path «$SHOTA»)"; BAD=1
fi
case "$APX" in
    "${GEOA%x*} ${GEOA#*x} | 204 0 0")
        echo "OK: A's client body is A's red, at the size the log declared" ;;
    *) echo "FAIL: A's body probe says «$APX», want «${GEOA%x*} ${GEOA#*x} | 204 0 0»"; BAD=1 ;;
esac
case "$ABAR" in
    *"| 52 101 164") echo "OK: ...under a titlebar wearing the focus blue" ;;
    *) echo "FAIL: A's bar probe says «$ABAR»"; BAD=1 ;;
esac
case "$BPX" in
    *"| 32 74 135")
        echo "OK: shooting covered B raised it first — the body is B's blue" ;;
    *) echo "FAIL: B's body probe says «$BPX», want blue 32 74 135"; BAD=1 ;;
esac
case "$BBAR" in
    *"| 136 138 133")
        echo "OK: ...and B was raised, not focused — the bar is the unfocus grey" ;;
    *) echo "FAIL: B's bar probe says «$BBAR», want 136 138 133"; BAD=1 ;;
esac

check_invariants "$LOG"
if grep -q 'WM: INVARIANT' "$LOG"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the shot is what the eye saw — raised, framed, exact"
exit $BAD
