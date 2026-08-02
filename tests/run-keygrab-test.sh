#!/bin/sh
# Regression: AN UNBOUND CHORD GIVES ITS GRAB BACK.
#
# The owner bound a bare `t`, took the binding away again, and the
# letter stayed dead — it reached neither the desk nor the client
# (2026-08-02). A top chord's grab is shared by everything under it,
# so no single unbind could drop it and none ever did; the key kept
# arriving at the WM, which had nothing to run and nothing to replay
# it with.
#
# So: bind `t`, and the desk answers while the client hears nothing;
# unbind it, and the letter is the client's again. And the sibling
# case, which is why the grab was left alone in the first place:
# under a prefix with two bindings, dropping ONE must not silence the
# other.
. "$(dirname "$0")/common.sh"
export DISPLAY=:100
rm -f /tmp/.X100-lock /tmp/.X11-unix/X100
Xvfb :100 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/keygrab-config"
mkdir -p "$HERE/keygrab-config"
cat > "$HERE/keygrab-config/tk9wm.tcl" <<'EOF'
set-welcome off
wm-bind t {puts "WM: the desk took t"} took-t
wm-bind {<Super>g a} {puts "WM: the desk took a"} took-a
wm-bind {<Super>g b} {puts "WM: the desk took b"} took-b
EOF

XDG_CONFIG_HOME="$HERE/keygrab-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-keygrab.log" 2>&1 &
WM=$!
sleep 1.5

q() { printf '%s\n' "$1" > "$HERE/keygrab-config/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$HERE/keygrab-config/q.tcl"; }

"$LINUX/whale" "$HERE/client-press.tcl" keyclient 240x120 "#729fcf" 60 \
    > "$HERE/keygrab-client.log" 2>&1 &
CL=$!
sleep 1.5
xdotool search --name keyclient windowfocus 2>/dev/null
sleep 0.5

# ---- bound: the desk answers, the client hears nothing ----
xdotool key t
sleep 0.5
BOUND=$(grep -c 'the desk took t' "$HERE/wm-keygrab.log" || true)
HEARD1=$(grep -c 'key t ' "$HERE/keygrab-client.log" || true)

# ---- unbound: the letter goes back to being the client's ----
q 'wm-unbind t' >/dev/null
sleep 0.5
xdotool key t
sleep 0.5
AFTER=$(grep -c 'the desk took t' "$HERE/wm-keygrab.log" || true)
HEARD2=$(grep -c 'key t ' "$HERE/keygrab-client.log" || true)
RELEASED=$(grep -c 'key top chord t released' "$HERE/wm-keygrab.log" || true)

# ---- the sibling case: one of two goes, the other still answers ----
q 'wm-unbind {<Super>g a}' >/dev/null
sleep 0.3
xdotool key super+g
sleep 0.3
xdotool key b
sleep 0.5
SIB=$(grep -c 'the desk took b' "$HERE/wm-keygrab.log" || true)
# ...and once the last one under it goes, the prefix is released too
q 'wm-unbind {<Super>g b}' >/dev/null
sleep 0.5
GONE=$(grep -c 'key top chord Super+g released' "$HERE/wm-keygrab.log" || true)

kill $CL $WM 2>/dev/null
sleep 0.5

echo "--- bound=$BOUND heard-while-bound=$HEARD1 after-unbind=$AFTER heard-after=$HEARD2"
echo "--- released=$RELEASED sibling-answered=$SIB prefix-released=$GONE"
echo "--- verdict"
if [ "$BOUND" = 1 ] && [ "$HEARD1" = 0 ]; then
    echo "OK: while bound, the desk answers t and the client never sees it"
else
    echo "FAIL: bound phase (desk=$BOUND client=$HEARD1)"
fi
if [ "$AFTER" = 1 ] && [ "$HEARD2" -ge 1 ] && [ "$RELEASED" -ge 1 ]; then
    echo "OK: unbinding gave the grab back — t is the client's letter again"
else
    echo "FAIL: after the unbind (desk=$AFTER client=$HEARD2 released=$RELEASED)"
fi
if [ "$SIB" -ge 1 ]; then
    echo "OK: dropping one binding under a prefix left its sibling answering"
else
    echo "FAIL: the sibling under Super+g stopped answering ($SIB)"
fi
if [ "$GONE" -ge 1 ]; then
    echo "OK: with the last binding under it gone, the prefix let its chord go"
else
    echo "FAIL: the prefix kept its grab with nothing under it ($GONE)"
fi
check_invariants "$HERE/wm-keygrab.log"
