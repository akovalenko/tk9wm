#!/bin/sh
# Regression for restart-in-place: a running WM, told to restart, must
# release its client, exec itself (same pid, same log fd) and adopt the
# client back — the client survives with its size and stays viewable.
#
# ...and the two windows that must come back the way they were LEFT: a
# minimized one still minimized (phase 3), a withdrawn one still gone
# (phase 4). Both are about what the X server does to a save-set on
# connection close, which is what a restart is.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-restart.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-restart.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "переживи рестарт" 320x240 "#8ae234" \
    > "$HERE/restart-client.log" &
CA=$!
wait_client "$HERE/wm-restart.log" 'переживи рестарт'
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-restart.log" | head -1)
echo "--- actor: $AID, WM pid $WM"

"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
# Wait for the SWEEP to settle, not for a guessed number of seconds:
# «adoption settled» is the line after every frame the sweep queued is
# on the glass, which is what the geometry read below is asking about.
# The counterpart guess in run-replace-test was measuring a moment that
# had not happened yet, and read as a WM bug for it (2026-08-19).
wait_for 15 grep -q 'adoption settled' "$HERE/wm-restart.log" \
    || echo "note: the fresh instance never settled its adoption"

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
trap 'stop_xservers; rm -f "$DOOMED"' EXIT

"$LINUX/whale" "$DOOMED" > "$HERE/wm-doomed.log" 2>&1 &
WM2=$!
wait_wm "$HERE/wm-doomed.log" $WM2
"$LINUX/whale" "$HERE/client.tcl" "переживи отказ" 300x200 "#fcaf3e" \
    > "$HERE/doomed-client.log" &
CB=$!
wait_client "$HERE/wm-doomed.log" 'переживи отказ'
BID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-doomed.log" | head -1)
echo "--- actor: $BID, WM pid $WM2"

rm -f "$DOOMED"                      # the pull, in one line
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
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
wait_wm "$HERE/wm-reicon.log" $WM3
"$LINUX/whale" "$HERE/client.tcl" "свернусь и переживу" 260x150 "#ad7fa8" \
    "" "" 40 > "$HERE/reicon-client.log" 2>&1 &
CC=$!
wait_client "$HERE/wm-reicon.log" 'свернусь и переживу'
RID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-reicon.log" | head -1)
xdotool key super+d
sleep 1.5
ST_MIN=$(xprop -id "$RID" WM_STATE 2>/dev/null | sed -n 's/.*window state: //p')
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
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

# --- phase 4: a WITHDRAWN window stays withdrawn -----------------------
# The other half of phase 3's question, and the answer nearly went the
# other way by itself. A client is put in the SAVE-SET when it is
# managed — crash insurance, so a window living inside one of our frames
# is handed back to the root rather than dying with it — and the X
# protocol's connection-close rule performs a MapWindow on every
# UNMAPPED member of that set, "even if it was not an inferior of a
# window created by the client". A restart IS a connection close. So a
# client that had withdrawn itself, long since unmanaged and handed back
# to the root, was MAPPED by the server at every restart and adopted by
# the incoming instance as an ordinary viewable window — the owner's
# runner and configurator, hidden on purpose and back on the screen
# (2026-08-19). Nothing in the WM's log looked wrong, because nothing in
# the WM had done it.
echo "--- phase 4: withdrawn across a restart"
"$LINUX/whale" "$WMTCL" > "$HERE/wm-hidden.log" 2>&1 &
WM4=$!
wait_wm "$HERE/wm-hidden.log" $WM4
"$LINUX/whale" "$HERE/client-hide.tcl" затворник 40 \
    > "$HERE/hidden-client.log" 2>&1 &
CH=$!
wait_client "$HERE/wm-hidden.log" 'затворник'
HID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-hidden.log" | head -1)
wait_for 10 grep -q 'withdrew itself' "$HERE/wm-hidden.log"
MAP_HID=$(xwininfo -id "$HID" 2>/dev/null | sed -n 's/.*Map State: //p')
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
sleep 3
MAP_H2=$(xwininfo -id "$HID" 2>/dev/null | sed -n 's/.*Map State: //p')
# The client's OWN reading, taken well after the restart — "did anybody
# map me while I was not looking" is the whole question, and only it can
# answer it. Waited for rather than slept past: the fixture takes it on
# its own clock.
wait_for 15 grep -q '^HIDE: mapped=' "$HERE/hidden-client.log"
CLIENT_H=$(sed -n 's/^HIDE: mapped=//p' "$HERE/hidden-client.log" | tail -1)
kill $WM4 $CH 2>/dev/null
echo "    hidden=$MAP_HID  after restart=$MAP_H2  (the client says mapped=$CLIENT_H)"

if [ "$MAP_HID" = "IsUnMapped" ] && [ "$MAP_H2" = "IsUnMapped" ]; then
    echo "OK: a window the client put away stayed away across the restart"
else
    echo "FAIL: hidden=$MAP_HID, after the restart $MAP_H2 — the save-set\
 mapped it behind everyone's back"; FAIL=1
fi
if [ "$CLIENT_H" = 0 ]; then
    echo "OK: ...and the client agrees it was never mapped"
else
    echo "FAIL: the client says mapped=$CLIENT_H — it is on screen and did\
 not put itself there"; FAIL=1
fi
if grep -q "adopting existing window $HID" "$HERE/wm-hidden.log"; then
    echo "FAIL: the fresh instance adopted a window nobody was showing"; FAIL=1
else
    echo "OK: ...and the fresh instance had nothing to adopt"
fi

exit $FAIL
