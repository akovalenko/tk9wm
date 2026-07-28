#!/bin/sh
# Regression for iconification — the ICCCM answer to WM_CHANGE_STATE.
#
# Phase 1 (default policy): a client iconifies itself; the WM must put
# it in IconicState for real — client unmapped, WM_STATE 3,
# _NET_WM_STATE_HIDDEN published, decoration off the screen, focus
# moved on — and it must stay MANAGED, so the window list still lists
# it (marked) and picking it there brings it back mapped and focused.
#
# Phase 2 (`set-minimize refuse`): the same request must be REFUSED
# audibly — WM_STATE re-stated as NormalState so a client that already
# minimized itself internally is told to come back (that is what makes
# the refusal reach wine's Win32 side), the window still mapped.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:93
rm -f /tmp/.X93-lock /tmp/.X11-unix/X93
Xvfb :93 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

key() { xdotool key "$@"; sleep 0.5; }
state() { xprop -id "$1" WM_STATE 2>/dev/null | sed -n 's/.*window state: //p'; }
mapstate() { xwininfo -id "$1" | sed -n 's/.*Map State: //p'; }
hidden() {
    xprop -id "$1" _NET_WM_STATE 2>/dev/null | grep -c _NET_WM_STATE_HIDDEN
}

# ---- phase 1: honored ----
"$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-iconify.log" 2>&1 &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client-iconify.tcl" свёртыш 16 3 \
    > "$HERE/iconify-client.log" 2>&1 &
CL=$!
sleep 2
WID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-iconify.log" | head -1)
echo "--- victim: $WID"
S0=$(state "$WID"); M0=$(mapstate "$WID")
sleep 3          # the client asks at t+3
S1=$(state "$WID"); M1=$(mapstate "$WID"); H1=$(hidden "$WID")
import -window root "$HERE/iconify-gone.png" 2>/dev/null \
    && echo "DRIVER: screenshot (iconic) -> $HERE/iconify-gone.png"

# the way back: the static window list, entry 1 (the desk holds one window)
key super+t
key w
key w
sleep 0.5
import -window root "$HERE/iconify-list.png" 2>/dev/null \
    && echo "DRIVER: screenshot (list) -> $HERE/iconify-list.png"
key 1
sleep 1
S2=$(state "$WID"); M2=$(mapstate "$WID"); H2=$(hidden "$WID")
import -window root "$HERE/iconify-back.png" 2>/dev/null \
    && echo "DRIVER: screenshot (restored) -> $HERE/iconify-back.png"
kill $WM $CL 2>/dev/null
sleep 1

# ---- phase 2: refused ----
rm -rf "$HERE/refuse-config"
mkdir -p "$HERE/refuse-config"
echo 'set-minimize refuse' > "$HERE/refuse-config/tk9wm.tcl"
XDG_CONFIG_HOME="$HERE/refuse-config" \
    "$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-iconrefuse.log" 2>&1 &
WM2=$!
sleep 1.5
"$LINUX/whale" "$HERE/client-iconify.tcl" отказыш 9 3 \
    > "$HERE/iconrefuse-client.log" 2>&1 &
CL2=$!
sleep 6
WID2=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-iconrefuse.log" | head -1)
S3=$(state "$WID2"); M3=$(mapstate "$WID2")
import -window root "$HERE/iconify-refused.png" 2>/dev/null \
    && echo "DRIVER: screenshot (refused) -> $HERE/iconify-refused.png"
kill $WM2 $CL2 2>/dev/null

echo "--- WM saw (phase 1):"
grep -E 'iconif|winlist pick|focus ->|parking' "$HERE/wm-iconify.log"
echo "--- client said (phase 1):"
grep CLIENT "$HERE/iconify-client.log"
echo "--- WM saw (phase 2):"
grep -E 'iconif|refus' "$HERE/wm-iconrefuse.log"
echo "--- client said (phase 2):"
grep CLIENT "$HERE/iconrefuse-client.log"

echo "--- verdict"
BAD=0
for L in "$HERE/wm-iconify.log" "$HERE/wm-iconrefuse.log"; do
    if grep -q 'BadAccess request=2' "$L"; then
        echo "FAIL: another WM owns this display — this run measured nothing"; BAD=1
    fi
    if grep -q 'soft failure' "$L"; then
        echo "FAIL: soft failures logged:"; grep 'soft failure' "$L"; BAD=1
    fi
done
echo "    states: before=$S0/$M0  iconic=$S1/$M1(hidden=$H1)  back=$S2/$M2(hidden=$H2)  refused=$S3/$M3"
if [ "$S1" = "Iconic" ] && [ "$M1" = "IsUnMapped" ]; then
    echo "OK: the request was honored — IconicState and the client unmapped"
else
    echo "FAIL: after the request the window is $S1/$M1, want Iconic/IsUnMapped"; BAD=1
fi
if [ "$H1" = "1" ]; then
    echo "OK: _NET_WM_STATE_HIDDEN published while iconic"
else
    echo "FAIL: no _NET_WM_STATE_HIDDEN while iconic"; BAD=1
fi
if grep -q 'winlist pick' "$HERE/wm-iconify.log" \
        && [ "$S2" = "Normal" ] && [ "$M2" = "IsViewable" ] && [ "$H2" = "0" ]; then
    echo "OK: the window list brought it back — Normal, viewable, not hidden"
else
    echo "FAIL: after the pick the window is $S2/$M2 (hidden=$H2)"; BAD=1
fi
if grep -q 'focus -> ' "$HERE/wm-iconify.log" && grep -q "deiconified $WID" "$HERE/wm-iconify.log"; then
    echo "OK: deiconify logged for the victim"
else
    echo "FAIL: no deiconify line for $WID"; BAD=1
fi
if grep -q 'iconify refused' "$HERE/wm-iconrefuse.log" \
        && [ "$S3" = "Normal" ] && [ "$M3" = "IsViewable" ]; then
    echo "OK: set-minimize refuse said no out loud and kept the window up"
else
    echo "FAIL: refuse phase left the window $S3/$M3"; BAD=1
fi
if grep -q 'handler error' "$HERE/wm-iconify.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-iconify.log"; BAD=1
fi
[ $BAD -eq 0 ] && echo "OK: iconification honored, reversible, and refusable"
