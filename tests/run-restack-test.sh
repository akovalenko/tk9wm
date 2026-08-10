#!/bin/sh
# Regression for the client's own restack request — the CWStackMode
# bit of a ConfigureRequest. XRaiseWindow (Tk's `raise .`, emacs's
# minibuffer-auto-raise surfacing a prompt) and XLowerWindow used to
# be dropped unread for a managed window; now they land on the
# policy's own raise/lower, layers intact. Also proved here: a
# conditional mode (top-if) is named in the log rather than silently
# eaten, and the verb next door — an EWMH activation, what
# `wmctrl -i -a` sends — raises AND focuses.
#
# Measured in pixels off the root, because a claim about stacking is
# a claim about what one can see: two overlapping actors in colours
# of their own, and the overlap pixel says who is on top.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-restack.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-restack.log" $WM

# нижний maps first, so верхний covers the overlap until нижний asks
# to be raised. Geometry gives both a USPosition claim, honored.
"$LINUX/whale" "$HERE/client.tcl" "нижний" 300x200+40+40 "#8ae234" "" "" 30 \
    > "$HERE/restack-a.log" 2>&1 &
CA=$!
wait_client "$HERE/wm-restack.log" 'нижний'
"$LINUX/whale" "$HERE/client.tcl" "верхний" 300x200+180+120 "#3465a4" "" "" 30 \
    > "$HERE/restack-b.log" 2>&1 &
CB=$!
wait_client "$HERE/wm-restack.log" 'верхний'

# The actor asked to move is нижний — first in manage order.
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-restack.log" \
    | sed -n 1p)
echo "--- actors: нижний=$AID"

px() { import -window root "$HERE/restack-shot.png" 2>/dev/null
       convert "$HERE/restack-shot.png" -format "%[pixel:p{$1,$2}]" info:; }
pixel_is() { [ "$(px "$1" "$2")" = "$3" ]; }
green='srgb(138,226,52)'      # нижний
blue='srgb(52,101,164)'       # верхний
FAIL=0
ok()  { echo "OK: $1"; }
bad() { echo "FAIL: $1"; FAIL=1; }

# Inside both client areas whatever the frames add around them.
PX=250; PY=180

wait_for 5 pixel_is $PX $PY $blue \
    && ok "baseline: верхний covers the overlap" \
    || bad "baseline: overlap is [$(px $PX $PY)], want верхний ($blue)"

"$WHALE_CLI" "$TOOLS/send-restack.tcl" "$DISPLAY" "$AID" above
wait_for 5 pixel_is $PX $PY $green \
    && ok "raise request surfaces нижний" \
    || bad "after raise: overlap is [$(px $PX $PY)], want нижний ($green)"

"$WHALE_CLI" "$TOOLS/send-restack.tcl" "$DISPLAY" "$AID" below
wait_for 5 pixel_is $PX $PY $blue \
    && ok "lower request sinks нижний" \
    || bad "after lower: overlap is [$(px $PX $PY)], want верхний ($blue)"

"$WHALE_CLI" "$TOOLS/send-restack.tcl" "$DISPLAY" "$AID" top-if
wait_for 5 grep -q "restack $AID top-if: unimplemented" "$HERE/wm-restack.log" \
    && ok "a conditional mode is heard and named" \
    || bad "top-if left no trace in the WM log"

# The activation verb: _NET_ACTIVE_WINDOW raises the group AND
# invites the focus — the recovery path emacs takes right after its
# raise (select-frame-set-input-focus is both calls back to back).
wmctrl -i -a "$AID"
wait_for 5 pixel_is $PX $PY $green \
    && ok "activation surfaces нижний" \
    || bad "after activation: overlap is [$(px $PX $PY)], want нижний ($green)"
wait_for 5 grep -q "focus -> $AID" "$HERE/wm-restack.log" \
    && ok "activation focused нижний" \
    || bad "no «focus -> $AID» after activation"

echo "--- restack lines the WM said:"
grep 'WM: restack\|WM: activation' "$HERE/wm-restack.log"
check_invariants "$HERE/wm-restack.log"

kill $WM 2>/dev/null
kill $CA $CB 2>/dev/null

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-restack.log"; then
    bad "another WM owns this display — this run measured nothing"
fi
[ "$FAIL" = 0 ] && echo "OK: client restack requests land on the policy's verbs" \
                || echo "FAIL: see above"
