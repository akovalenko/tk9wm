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

kill $WM $CA $CB 2>/dev/null
check_invariants "$LOG" || FAIL=1
if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"
    FAIL=1
fi
exit $FAIL
