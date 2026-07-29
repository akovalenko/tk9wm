#!/bin/sh
# Regression for the modifier mouse gestures: hold <Super> and carry a
# window from anywhere on it (button 1), or resize it from the nearest
# corner (button 3) — the only mouse handle a window with `decor none`
# has at all. Plus the root window's own cursor, which the WM now sets
# instead of leaving the server's X_cursor for xsetroot to fix.
#
# Actors:
#   таскаемый   ordinary decorated client that REPORTS every press it
#               receives — the super-drag must not reach it, the plain
#               click must
#   голый       decor none: no titlebar, no border, nothing to grab
. "$(dirname "$0")/common.sh"
export DISPLAY=:73
rm -f /tmp/.X73-lock /tmp/.X11-unix/X73
Xvfb :73 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
trap 'kill $XVFB 2>/dev/null; rm -rf "$CONF"' EXIT
cat > "$CONF/tk9wm.tcl" <<'EOF'
wm-style {filter -title голый} {decor none}
EOF
sleep 1

LOG="$HERE/wm-drag.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client-press.tcl" таскаемый 240x120 "#729fcf" 30 \
    > "$HERE/drag-client.log" 2>&1 &
sleep 0.8
"$LINUX/whale" "$HERE/client-press.tcl" голый 200x100 "#8ae234" 30 \
    > "$HERE/drag-bare.log" 2>&1 &
sleep 2

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
DRAGGED=$1; BARE=$2

geom() {
    xwininfo -id "$1" | awk '/Width:/ {w=$2} /Height:/ {h=$2}
        /Absolute upper-left X/ {x=$NF} /Absolute upper-left Y/ {y=$NF}
        END {print w "x" h "+" x "+" y}'
}
at() { geom "$1" | sed 's/.*+\([0-9-]*\)+\([0-9-]*\)/\1 \2/'; }
size() { geom "$1" | sed 's/+.*//'; }
check() {
    if [ "$2" = "$3" ]; then echo "OK: $1 — $3"; else
        echo "FAIL: $1 — got $3, want $2"; fi
}
# press inside a window and drag: $1 = client id, $2 = button,
# $3/$4 = delta, $5 = modifier (empty for none)
drag() {
    set -- $(at "$1") "$2" "$3" "$4" "$5"
    PX=$(( $1 + 40 )); PY=$(( $2 + 40 ))
    if [ -n "$6" ]; then xdotool keydown "$6"; fi
    xdotool mousemove $PX $PY mousedown "$3" \
            mousemove $((PX + $4)) $((PY + $5)) sleep 0.2 mouseup "$3"
    if [ -n "$6" ]; then xdotool keyup "$6"; fi
    sleep 0.5
}

BEFORE=$(at "$DRAGGED")
drag "$DRAGGED" 1 120 60 super
AFTER=$(at "$DRAGGED")
WANT=$(echo "$BEFORE" | awk '{print $1 + 120, $2 + 60}')
PRESSES_AFTER_SUPER=$(grep -c 'press' "$HERE/drag-client.log")

# ...and the same drag without the modifier is the CLIENT's click: the
# window must not budge from where the carry left it, and the client
# must have heard the press
STILL=$(at "$DRAGGED")
drag "$DRAGGED" 1 60 60 ""
PLAIN=$(at "$DRAGGED")
PRESSES_AFTER_PLAIN=$(grep -c 'press' "$HERE/drag-client.log")

BARE_BEFORE=$(at "$BARE")
drag "$BARE" 1 -80 40 super
BARE_AFTER=$(at "$BARE")
BARE_WANT=$(echo "$BARE_BEFORE" | awk '{print $1 - 80, $2 + 40}')

# button 3 near the top-left of the window pulls the nw corner: the
# frame's far corner stays put and the client grows by the drag
BARE_SIZE=$(size "$BARE")
drag "$BARE" 3 -30 -20 super
BARE_SIZE2=$(size "$BARE")
BARE_SIZE_WANT=$(echo "$BARE_SIZE" | awk -F x '{print $1 + 30 "x" $2 + 20}')

import -display :73 -window root "$HERE/drag-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/drag-test.png"
kill $WM 2>/dev/null
pkill -f "$HERE/client-press.tcl" 2>/dev/null

echo "--- actors: dragged=$DRAGGED bare=$BARE"
grep -E '^WM: (gesture|root cursor|frame \.f[0-9]+ for)' "$LOG"
echo "--- verdict"
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
check "super+drag carried the window" "$WANT" "$AFTER"
check "the client never saw the super-press" "0" "$PRESSES_AFTER_SUPER"
check "a plain drag left the window where it was" "$STILL" "$PLAIN"
if [ "$PRESSES_AFTER_PLAIN" -gt 0 ]; then
    echo "OK: ...and the client DID see that one ($PRESSES_AFTER_PLAIN)"
else
    echo "FAIL: the plain press never reached the client"
fi
check "an undecorated window has a handle after all" "$BARE_WANT" "$BARE_AFTER"
check "super+button3 pulled the nearest corner" "$BARE_SIZE_WANT" "$BARE_SIZE2"
if xprop -root | grep -q .; then :; fi
# X gives no way to ask a window what cursor it wears, so the check is
# on the log — and it has to be a POSITIVE one. This used to assert
# only the absence of a soft failure, which passed for weeks while the
# call was not being made at all: the default reached the screen from
# policy-apply, and policy-apply runs on a config reload only. An
# assertion that cannot fail is not an assertion.
if grep -q 'soft failure — root cursor' "$LOG"; then
    echo "FAIL: the root cursor was refused: $(grep 'root cursor' "$LOG")"
elif grep -q '^WM: root cursor left_ptr' "$LOG"; then
    echo "OK: the root cursor was set at startup, with no config asking"
else
    echo "FAIL: nothing set the root cursor — the default never reached the screen"
fi
if grep -q 'handler error\|pointer router error' "$LOG"; then
    echo "FAIL: handler errors present:"
    grep 'handler error\|pointer router error' "$LOG"
fi
