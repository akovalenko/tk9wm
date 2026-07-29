#!/bin/sh
# Regression for restart-in-place: a running WM, told to restart, must
# release its client, exec itself (same pid, same log fd) and adopt the
# client back — the client survives with its size and stays viewable.
. "$(dirname "$0")/common.sh"
export DISPLAY=:90
rm -f /tmp/.X90-lock /tmp/.X11-unix/X90
Xvfb :90 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-restart.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "переживи рестарт" 320x240 "#8ae234" \
    > "$HERE/restart-client.log" &
CA=$!
sleep 1.5
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-restart.log" | head -1)
echo "--- actor: $AID, WM pid $WM"

"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" :90
sleep 2.5

STATE=$(xwininfo -id "$AID" 2>/dev/null | awk '/Map State:/ {print $3}')
GEOM=$(xwininfo -id "$AID" 2>/dev/null | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
ALIVE=0; kill -0 $WM 2>/dev/null && ALIVE=1
kill $WM $CA 2>/dev/null

echo "--- verdict"
FAIL=0
if grep -q 'restart requested' "$HERE/wm-restart.log"; then
    echo "OK: restart accepted"
else
    echo "FAIL: no restart line in the log"; FAIL=1
fi
ARMED=$(grep -c 'redirect armed' "$HERE/wm-restart.log")
if [ "$ARMED" = "2" ]; then
    echo "OK: the log holds two lifetimes (redirect armed twice, same fd)"
else
    echo "FAIL: 'redirect armed' seen $ARMED times, want 2"; FAIL=1
fi
if grep -q "adopting existing window $AID" "$HERE/wm-restart.log"; then
    echo "OK: the new WM adopted $AID"
else
    echo "FAIL: $AID was not adopted after restart"; FAIL=1
fi
if [ "$ALIVE" = "1" ] && [ "$STATE" = "IsViewable" ] && [ "$GEOM" = "320x240" ]; then
    echo "OK: same pid alive, client viewable at $GEOM"
else
    echo "FAIL: pid alive=$ALIVE, client state=$STATE geom=$GEOM"; FAIL=1
fi

# --- phase 2: the entry script vanishes under a running WM -----------
# A rename in the checkout, or a pull that renames the entry script.
# execv would still SUCCEED — it replaces us with the interpreter, and
# it is the interpreter that then dies on the missing file — so the
# restart must be refused BEFORE anything is released. The old order
# released every client first and found out afterwards, which with
# .Xsession exec'ing the WM turned the restart chord into a logout.
echo "--- phase 2: entry script deleted under the running WM"
DOOMED="$ROOT/restart-doomed.tcl"
cp "$WMTCL" "$DOOMED"
trap 'kill $XVFB 2>/dev/null; rm -f "$DOOMED"' EXIT

"$LINUX/whale" "$DOOMED" > "$HERE/wm-doomed.log" 2>&1 &
WM2=$!
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" "переживи отказ" 300x200 "#fcaf3e" \
    > "$HERE/doomed-client.log" &
CB=$!
sleep 1.5
BID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-doomed.log" | head -1)
echo "--- actor: $BID, WM pid $WM2"

rm -f "$DOOMED"                      # the pull, in one line
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" :90
sleep 2

STATE2=$(xwininfo -id "$BID" 2>/dev/null | awk '/Map State:/ {print $3}')
PARENT2=$(xwininfo -id "$BID" -children 2>/dev/null \
    | sed -n 's/^  Parent window id: \(0x[0-9a-f]*\).*/\1/p')
ROOTID=$(xwininfo -root 2>/dev/null | sed -n 's/^xwininfo: Window id: \(0x[0-9a-f]*\).*/\1/p')
ALIVE2=0; kill -0 $WM2 2>/dev/null && ALIVE2=1
LIVES2=$(grep -c 'redirect armed' "$HERE/wm-doomed.log")
kill $WM2 $CB 2>/dev/null

if grep -q 'restart REFUSED' "$HERE/wm-doomed.log"; then
    echo "OK: the restart was refused, not attempted"
else
    echo "FAIL: no refusal in the log — it tried to exec a script that is gone"
    FAIL=1
fi
if [ "$ALIVE2" = "1" ] && [ "$LIVES2" = "1" ]; then
    echo "OK: the WM is still up and never restarted (one lifetime)"
else
    echo "FAIL: WM alive=$ALIVE2, lifetimes=$LIVES2 (want 1, alive)"; FAIL=1
fi
if [ "$STATE2" = "IsViewable" ] && [ -n "$PARENT2" ] && [ "$PARENT2" != "$ROOTID" ]; then
    echo "OK: nothing was released — the client is still framed ($PARENT2)"
else
    echo "FAIL: client state=$STATE2 parent=«$PARENT2» root=«$ROOTID»"; FAIL=1
fi

# --- phase 3: a MINIMIZED window survives the restart minimized ------
# WM_STATE is the only place "somebody minimized this" survives an
# execv, so the outgoing instance must leave IconicState on it (not
# Withdrawn) and the incoming one must read it back. Getting this wrong
# does not look like a WM bug from the outside: the window returns
# mapped but BLANK, because gtk/gecko/electron still believe themselves
# iconic and will not paint into a window the save-set remapped behind
# their backs. xterm and emacs paint anyway, which is what made it look
# application-specific.
echo "--- phase 3: minimized across a restart"
CONF="$HERE/restart-config"
rm -rf "$CONF"; mkdir -p "$CONF"
echo 'wm-bind {<Super>d} {Apply-To-Matching always Minimize}' \
    > "$CONF/tk9wm.tcl"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" \
    > "$HERE/wm-reicon.log" 2>&1 &
WM3=$!
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" "свернусь и переживу" 260x150 "#ad7fa8" \
    "" "" 40 > "$HERE/reicon-client.log" 2>&1 &
CC=$!
sleep 2
RID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-reicon.log" | head -1)
xdotool key super+d
sleep 1.5
ST_MIN=$(xprop -id "$RID" WM_STATE 2>/dev/null | sed -n 's/.*window state: //p')
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" :90
sleep 3
ST_AFTER=$(xprop -id "$RID" WM_STATE 2>/dev/null | sed -n 's/.*window state: //p')
MAP_AFTER=$(xwininfo -id "$RID" 2>/dev/null | sed -n 's/.*Map State: //p')
PAR_AFTER=$(xwininfo -id "$RID" -children 2>/dev/null \
    | sed -n 's/^  Parent window id: \(0x[0-9a-f]*\).*/\1/p')
ROOT3=$(xwininfo -root 2>/dev/null | sed -n 's/^xwininfo: Window id: \(0x[0-9a-f]*\).*/\1/p')
# ...and the way back still works: the static window list, entry 1
xdotool key super+t; sleep 0.3; xdotool key w; sleep 0.3; xdotool key w
sleep 0.5
xdotool key 1
sleep 1.5
ST_BACK=$(xprop -id "$RID" WM_STATE 2>/dev/null | sed -n 's/.*window state: //p')
MAP_BACK=$(xwininfo -id "$RID" 2>/dev/null | sed -n 's/.*Map State: //p')
echo "    minimized=$ST_MIN  after restart=$ST_AFTER/$MAP_AFTER parent=$PAR_AFTER  restored=$ST_BACK/$MAP_BACK"
kill $WM3 $CC 2>/dev/null

if [ "$ST_MIN" = "Iconic" ] && [ "$ST_AFTER" = "Iconic" ] \
        && [ "$MAP_AFTER" = "IsUnMapped" ]; then
    echo "OK: it came back minimized, not silently restored"
else
    echo "FAIL: minimized=$ST_MIN, after the restart $ST_AFTER/$MAP_AFTER"; FAIL=1
fi
if [ -n "$PAR_AFTER" ] && [ "$PAR_AFTER" != "$ROOT3" ]; then
    echo "OK: ...and it is MANAGED while minimized (framed, so the list has it)"
else
    echo "FAIL: after the restart its parent is «$PAR_AFTER» (root is $ROOT3) —"
    echo "      adopted and then dropped, or never adopted"; FAIL=1
fi
if [ "$ST_BACK" = "Normal" ] && [ "$MAP_BACK" = "IsViewable" ]; then
    echo "OK: ...and the window list still brings it back"
else
    echo "FAIL: after the pick it is $ST_BACK/$MAP_BACK"; FAIL=1
fi
# The window must not be offered the focus on the way in. It is about
# to be unmapped, and a client that answers a WM_TAKE_FOCUS invitation
# for a window that vanishes half a breath later is left believing it
# holds a focus the server has already moved on from — keyboard-dead
# until something makes it re-decide, which is what clicking it does.
if awk -v id="$RID" '
        /adopted minimized/ && index($0, id) { seen = 1 }
        seen && /deiconified/ && index($0, id) { exit }
        seen && /focus ->/ && index($0, id) { bad = 1 }
        END { exit !bad }' "$HERE/wm-reicon.log"; then
    echo "FAIL: the focus was offered to a window on its way to minimized:"
    grep -n 'focus ->' "$HERE/wm-reicon.log" | head -4; FAIL=1
else
    echo "OK: adopted minimized without being offered the focus first"
fi
if grep -q 'withdrew itself' "$HERE/wm-reicon.log"; then
    echo "FAIL: an unmap of OURS was read as the client withdrawing:"
    grep 'withdrew itself' "$HERE/wm-reicon.log"; FAIL=1
else
    echo "OK: none of our own unmaps was mistaken for a withdrawal"
fi

exit $FAIL
