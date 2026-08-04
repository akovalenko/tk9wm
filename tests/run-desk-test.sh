#!/bin/sh
# Regression for VIRTUAL DESKS — fvwm's Desks: several independent sets
# of windows on one screen, switching by visibility and nothing else.
#
#   - a window on another desk is OFF THE SCREEN but not iconic: its
#     WM_STATE stays NormalState, which is the owner's call
#     (2026-08-04) and the reason clients that paint by their state
#     (emacs, telega) keep painting;
#   - sticky windows are on every desk;
#   - the keys: Super+N goes, Super+Shift+N sends, and the digits of
#     the NUMPAD do the same — with NumLock on the keypad sends KP_n
#     and a chord bound to the digit used to be dead over there;
#   - the help collapses the family to ONE line, «Super+1..4», instead
#     of listing a row per desk;
#   - EWMH says all of it: _NET_NUMBER_OF_DESKTOPS, _NET_CURRENT_DESKTOP
#     and _NET_WM_DESKTOP per window.
. "$(dirname "$0")/common.sh"
export DISPLAY=:91
rm -f /tmp/.X91-lock /tmp/.X11-unix/X91
Xvfb :91 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

CONF="$HERE/desk-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-desks 4
wm-style {filter -title липкий} {desk sticky}
wm-widget где -type desks -on workarea -place {left top} -style text
EOF

LOG="$HERE/wm-desk.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5

FAIL=0
ok()  { echo "OK: $1"; }
bad() { echo "FAIL: $1"; FAIL=1; }
viewable() {   # is this client's window on the screen?
    xwininfo -id "$1" 2>/dev/null | sed -n 's/^  Map State: \(.*\)$/\1/p'
}
wmstate() { xprop -id "$1" WM_STATE 2>/dev/null | sed -n 's/.*window state: \(.*\)/\1/p'; }
deskof()  { xprop -id "$1" _NET_WM_DESKTOP 2>/dev/null | sed 's/.*= //'; }
curdesk() { xprop -root _NET_CURRENT_DESKTOP | sed 's/.*= //'; }
ndesks()  { xprop -root _NET_NUMBER_OF_DESKTOPS | sed 's/.*= //'; }

"$LINUX/whale" "$HERE/client.tcl" "первый" 240x120+60+60 "#8ae234" "" "" 60 \
    > "$HERE/desk-a.log" 2>&1 &
CA=$!
sleep 1.2
"$LINUX/whale" "$HERE/client.tcl" "липкий" 200x100+400+60 "#fcaf3e" "" "" 60 \
    > "$HERE/desk-b.log" 2>&1 &
CB=$!
sleep 1.5
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 1p)
BID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 2p)
echo "--- actors: обычный $AID, липкий $BID; desks $(ndesks), on $(curdesk)"

if [ "$(ndesks)" = "4" ]; then
    ok "four desks are advertised"
else
    bad "_NET_NUMBER_OF_DESKTOPS is $(ndesks), want 4"
fi
if [ "$(deskof "$BID")" = "4294967295" ]; then
    ok "the sticky window says so in _NET_WM_DESKTOP"
else
    bad "the sticky window's desk is $(deskof "$BID"), want 4294967295"
fi

# --- switch away by key, and look at what happened ----------------
xdotool key --clearmodifiers super+2
sleep 1
echo "--- after Super+2: on desk $(curdesk); первый $(viewable "$AID")/$(wmstate "$AID"), липкий $(viewable "$BID")"
if [ "$(curdesk)" = "1" ]; then
    ok "Super+2 went to the second desk"
else
    bad "the current desk is $(curdesk), want 1"
fi
if [ "$(viewable "$AID")" = "IsUnviewable" ] || [ "$(viewable "$AID")" = "IsUnMapped" ]; then
    ok "...and the window of the first desk left the screen"
else
    bad "the other desk's window is still mapped ($(viewable "$AID"))"
fi
if [ "$(wmstate "$AID")" = "Normal" ]; then
    ok "...but its WM_STATE stays NORMAL — it is elsewhere, not minimized"
else
    bad "the window elsewhere is in state «$(wmstate "$AID")», want Normal"
fi
if [ "$(viewable "$BID")" = "IsViewable" ]; then
    ok "...and the sticky window is here too"
else
    bad "the sticky window did not follow ($(viewable "$BID"))"
fi

# --- the numpad twin: Super+KP_1 must be the same key --------------
xdotool key --clearmodifiers super+KP_1
sleep 1
if [ "$(curdesk)" = "0" ]; then
    ok "Super+KP_1 (the numpad digit) went back to the first desk"
else
    bad "the numpad digit did nothing — desk is $(curdesk)"
fi
if [ "$(viewable "$AID")" = "IsViewable" ]; then
    ok "...and the window came back to the screen"
else
    bad "the window did not come back ($(viewable "$AID"))"
fi

# --- send a window away, and the desk does NOT follow --------------
# The send acts on the FOCUSED window, and coming back to this desk
# focused whatever was most recent — which is the sticky one. Aim
# first, or the leg measures the wrong actor (it did, on the first
# run, and the WM was right).
xdotool windowactivate "$AID"
sleep 0.8
xdotool key --clearmodifiers super+shift+3
sleep 1
echo "--- after Super+Shift+3: on desk $(curdesk); первый desk $(deskof "$AID"), $(viewable "$AID")"
if [ "$(curdesk)" = "0" ]; then
    ok "sending a window away leaves you where you are"
else
    bad "the send took the desk with it ($(curdesk))"
fi
if [ "$(deskof "$AID")" = "2" ]; then
    ok "...and the window says it lives on the third desk now"
else
    bad "the sent window's desk is $(deskof "$AID"), want 2"
fi

# --- the pile comes back the way it left --------------------------
# The cure for the switch flicker is an ORDER (topmost first, each next
# seated under it), so what it must be measured by is the order: two
# overlapping windows, away and back, and the one that was on top is
# still on top. The one-batch line beside it says the arrivals were not
# mapped one at a time with the screen redrawn between them.
xdotool key --clearmodifiers super+1
sleep 0.8
"$LINUX/whale" "$HERE/client.tcl" "нижний" 260x200+100+200 "#3465a4" "" "" 40 \
    > "$HERE/desk-c.log" 2>&1 &
CC=$!
sleep 1.2
"$LINUX/whale" "$HERE/client.tcl" "верхний" 260x200+160+260 "#ef2929" "" "" 40 \
    > "$HERE/desk-d.log" 2>&1 &
CD=$!
sleep 1.5
px() { import -window root "$HERE/desk-shot.png" 2>/dev/null
       convert "$HERE/desk-shot.png" -format "%[pixel:p{$1,$2}]" info:; }
OVER="200 300"     # where the two of them overlap
BEFORE=$(px $OVER)
xdotool key --clearmodifiers super+2
sleep 1
xdotool key --clearmodifiers super+1
sleep 1.5
AFTER=$(px $OVER)
BATCH=$(grep -ac "WM: desk 0: 2 shown" "$LOG")
echo "--- overlap $BEFORE -> away and back -> $AFTER (batches: $BATCH)"
if [ "$BEFORE" = "srgb(239,41,41)" ]; then
    ok "the later window is on top to start with"
else
    bad "the pile did not start the way it was built ($BEFORE)"
fi
if [ "$AFTER" = "$BEFORE" ]; then
    ok "...and the pile comes back in the same order after a round trip"
else
    bad "the round trip reordered the pile ($BEFORE -> $AFTER)"
fi
if [ "$BATCH" -ge 1 ]; then
    ok "...shown in ONE batch, not one window at a time"
else
    bad "the arrivals were not batched"
fi

# --- a minimized window keeps its desk ----------------------------
# Minimizing moves nothing, so restoring must move nothing either. The
# restore here is the one with NO HAND behind it — the client mapping
# itself again — because every road a hand takes (a panel button, a row
# of the list) goes through the desk first and would hide the bug.
# ...on «нижний», whose desk nothing has touched: первый was sent to
# the third desk two legs ago, and a leg that assumed otherwise would
# be measuring its own forgetfulness (it did, on the first run).
NID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 3p)
xdotool key --clearmodifiers super+1
sleep 0.8
xdotool windowminimize "$NID"
sleep 1
MINSTATE=$(wmstate "$NID")
xdotool key --clearmodifiers super+2
sleep 1
xdotool windowmap "$NID"        ;# the client comes back by itself
sleep 1.2
AWAY=$(viewable "$NID")
xdotool key --clearmodifiers super+1
sleep 1.2
HOME=$(viewable "$NID")
echo "--- minimized ($MINSTATE), restored on the wrong desk: $AWAY; back home: $HOME"
if [ "$MINSTATE" = "Iconic" ]; then
    ok "a minimize is an ICONIC state, desks or no desks"
else
    bad "the minimized window is in state «$MINSTATE», want Iconic"
fi
case $AWAY in
    IsUnMapped|IsUnviewable)
        ok "...and restoring it from another desk does not drag it here" ;;
    *) bad "the restored window appeared on the wrong desk ($AWAY)" ;;
esac
if [ "$HOME" = "IsViewable" ]; then
    ok "...it is waiting on its own desk when you go back"
else
    bad "the restored window is not on its own desk either ($HOME)"
fi

# --- the indicator answers "where am I" ---------------------------
# There is no pager and none is wanted, so the standing fact of which
# desk one is on lives in a widget. It is EVENT-driven (nothing polls
# for a desk change), which is the thing to prove: switch, and the
# pixels where it sits are not the pixels they were.
WID1=$(convert "$HERE/desk-shot.png" -crop 60x30+0+0 -format "%#" info: 2>/dev/null)
xdotool key --clearmodifiers super+4
sleep 1.2
import -window root "$HERE/desk-shot.png" 2>/dev/null
WID2=$(convert "$HERE/desk-shot.png" -crop 60x30+0+0 -format "%#" info: 2>/dev/null)
xdotool key --clearmodifiers super+1
sleep 1.2
if [ -n "$WID1" ] && [ "$WID1" != "$WID2" ]; then
    ok "the desk indicator repainted when the desk changed"
else
    bad "the indicator did not follow the switch ($WID1 / $WID2)"
fi

# --- the help says it in ONE line ----------------------------------
xdotool key --clearmodifiers super+h
sleep 1
xdotool key Escape
HELP=$(grep -a 'WM: key echo (help)' "$LOG" | tail -1)
echo "--- help: $HELP"
case "$HELP" in
    *"Super+1..4"*) ok "the help collapses the family to Super+1..4" ;;
    *)              bad "the help does not show a collapsed range" ;;
esac
case "$HELP" in
    *"Super+2 "*|*"Super+3 "*)
        bad "the help still lists the desks one by one" ;;
    *)  ok "...and does not list them one by one" ;;
esac
case "$HELP" in
    *"desk N"*) ok "...with the digit standing as N in the words" ;;
    *)          bad "the collapsed row lost its wording" ;;
esac

kill $WM $CA $CB $CC $CD 2>/dev/null
check_invariants "$LOG" || FAIL=1
if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"
    FAIL=1
fi
exit $FAIL
