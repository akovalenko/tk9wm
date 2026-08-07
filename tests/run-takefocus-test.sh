#!/bin/sh
# Regression for ICCCM WM_TAKE_FOCUS (live report, 2026-07-28: smsrc
# under Wine went keyboard-deaf after an alt-tab return — Wine turns
# a bare FocusIn into no Windows-level activation, but honors the
# WM_TAKE_FOCUS ClientMessage). Every focus-to of a client that
# advertises the protocol must be accompanied by the message; a
# client that does not advertise it must never get one.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/takefocus-config"
mkdir -p "$HERE/takefocus-config"
cat > "$HERE/takefocus-config/tf-client.tcl" <<'EOF'
package require Tk
chan configure stdout -buffering line
wm title . берущий
wm geometry . 240x120
label .l -text WM_TAKE_FOCUS -background #ad7fa8
pack .l -expand 1 -fill both
wm protocol . WM_TAKE_FOCUS {puts "CLIENT: got WM_TAKE_FOCUS"}
after 20000 exit
vwait ::forever
EOF
: > "$HERE/takefocus-config/tk9wm.tcl"   ;# stock behavior, no config

XDG_CONFIG_HOME="$HERE/takefocus-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-takefocus.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/takefocus-config/tf-client.tcl" \
    > "$HERE/takefocus-client.log" 2>&1 &
TF=$!
sleep 1.5              # managed and focused -> message #1

"$LINUX/whale" "$HERE/client.tcl" обычный 240x120 "#729fcf" "" "" 20 &
CB=$!
sleep 1.5              # the plain client holds the focus now

xdotool keydown alt key Tab; xdotool keyup alt   # quick toggle back
sleep 1                # -> message #2 for the take-focus client

kill $WM $TF $CB 2>/dev/null

echo "--- take-focus lines:"
grep -E 'TAKE_FOCUS|focus ->' "$HERE/wm-takefocus.log" | tail -8
grep 'CLIENT' "$HERE/takefocus-client.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-takefocus.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
TFID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-takefocus.log" | head -1)
SENT=$(grep -c "focus -> $TFID: sending WM_TAKE_FOCUS" "$HERE/wm-takefocus.log")
if [ "$SENT" -ge 2 ]; then
    echo "OK: the WM sent WM_TAKE_FOCUS on manage and on the alt-tab return ($SENT)"
else
    echo "FAIL: $SENT send lines for $TFID, want at least 2"
fi
GOT=$(grep -c 'CLIENT: got WM_TAKE_FOCUS' "$HERE/takefocus-client.log")
if [ "$GOT" -ge 2 ] && [ "$GOT" = "$SENT" ]; then
    echo "OK: the client saw every message ($GOT)"
else
    echo "FAIL: client saw $GOT messages, WM sent $SENT"
fi
CBID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-takefocus.log" | sed -n 2p)
if grep -q "focus -> $CBID: sending WM_TAKE_FOCUS" "$HERE/wm-takefocus.log"; then
    echo "FAIL: the plain client got WM_TAKE_FOCUS it never advertised"
else
    echo "OK: the plain client was never messaged"
fi
if grep -q 'handler error' "$HERE/wm-takefocus.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-takefocus.log"
fi
