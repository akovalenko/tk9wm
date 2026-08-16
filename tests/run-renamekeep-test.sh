#!/bin/sh
# Regression for the rename's persistence — the template ON the window
# (_TK9WM_TITLE_TEMPLATE, read back at every manage):
#
#   рестарт   a hand rename survives a desk restart: the outgoing
#             instance leaves the template on the client, the adopt
#             sweep reads it back, and %t goes on following the
#             client's renames in the new lifetime
#   стиль     a style-said title leaves NO template on the client and
#             comes back as a style after the restart — the restart
#             invents no rename
#   пусто     the empty answer deletes the property, so the next
#             restart resurrects nothing
#   withdraw  an ordinary withdraw sweeps the template AND the visible
#             name off the window — the next manager meets a clean
#             client — while the exit sweep (restart) leaves them
#   пред-имя  a template set on a window BEFORE it maps is adopted at
#             manage: a launcher can pre-name its window, no box
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1; }
LOG="$HERE/wm-renamekeep.log"
CONF="$HERE/renamekeep-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
wm-style {filter -title {стильный *}} {title {стиль: %t}}
wm-bind {<Super>1} Rename
EOF

askw() {   # eval in the WM
    printf '%s\n' "$1" > "$CONF/q.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1
}
askq() {   # eval in the ui host
    printf '%s\n' "$1" > "$CONF/hq.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm-ui "$CONF/hq.tcl" 2>&1
}
sendc() {  # eval in the renaming client
    printf '%s\n' "$1" > "$CONF/c.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" renamec "$CONF/c.tcl" 2>&1
}
sendp() {  # eval in the pre-named client
    printf '%s\n' "$1" > "$CONF/p.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" prenamec "$CONF/p.tcl" 2>&1
}
box_up()   { [ -n "$(xdotool search --class Tk9wmGadget 2>/dev/null)" ]; }
box_gone() { [ -z "$(xdotool search --class Tk9wmGadget 2>/dev/null)" ]; }
vname_is()     { xprop -id "$1" _NET_WM_VISIBLE_NAME | grep -qF "= \"$2\""; }
vname_absent() { xprop -id "$1" _NET_WM_VISIBLE_NAME | grep -q 'not found'; }
tpl_is()       { xprop -id "$1" _TK9WM_TITLE_TEMPLATE | grep -qF "= \"$2\""; }
tpl_absent()   { xprop -id "$1" _TK9WM_TITLE_TEMPLATE | grep -q 'not found'; }

BAD=0
ok()  { echo "OK: $1"; }
bad() { echo "FAIL: $1"; BAD=1; }
check_name() {   # label id want — poll, then say what actually stands
    if wait_for 10 vname_is "$2" "$3"; then ok "$1 — «$3»"
    else bad "$1 — want «$3», got: $(xprop -id "$2" _NET_WM_VISIBLE_NAME)"; fi
}
check_name_absent() {
    if wait_for 10 vname_absent "$2"; then ok "$1 — no visible name stands"
    else bad "$1 — still: $(xprop -id "$2" _NET_WM_VISIBLE_NAME)"; fi
}
check_tpl() {
    if wait_for 10 tpl_is "$2" "$3"; then ok "$1 — template «$3» on the window"
    else bad "$1 — want «$3», got: $(xprop -id "$2" _TK9WM_TITLE_TEMPLATE)"; fi
}
check_tpl_absent() {
    if wait_for 10 tpl_absent "$2"; then ok "$1 — no template on the window"
    else bad "$1 — still: $(xprop -id "$2" _TK9WM_TITLE_TEMPLATE)"; fi
}
focused_is() { [ "$(askw "expr {\$::focused == $1}")" = "1" ]; }
click_win() {   # focus a window by clicking inside its client area
    _xy=$(xwininfo -id "$1" | awk '/Absolute upper-left X/ {x=$NF}
        /Absolute upper-left Y/ {y=$NF} /Width:/ {w=$NF} /Height:/ {h=$NF}
        END {print int(x+w/2), int(y+h/2)}')
    xdotool mousemove --sync $_xy click 1
    wait_for 10 focused_is "$(($1 + 0))" \
        || echo "note: the click on $1 never took the focus"
}
rename_to() {   # id text — the real road: the box, primed, retyped
    click_win "$1"
    key super+1
    wait_for 20 box_up || bad "no rename box came up over $1"
    askq "ui-field-set .ask.b.f {$2}"
    key Return
    wait_for 10 box_gone
}

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

"$LINUX/whale" "$HERE/client-rename.tcl" > "$HERE/rename-c.log" 2>&1 &
CA=$!
wait_client "$LOG" 'рен старт'
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | head -1)
ADEC=$((AID + 0))

# ---- a hand rename, through the real box ----
rename_to "$AID" 'п: %t'
check_name "the rename stands" "$AID" "п: рен старт"
check_tpl "...and rides the window" "$AID" "п: %t"

"$LINUX/whale" "$HERE/client.tcl" "стильный сосед" 280x160 "#8ae234" \
    > "$HERE/renamekeep-b.log" 2>&1 &
CB=$!
wait_client "$LOG" 'стильный сосед'
BID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 2p)
BDEC=$((BID + 0))
echo "--- actors: renamed $AID, styled $BID"
check_name "the neighbour wears the style title" "$BID" "стиль: стильный сосед"
check_tpl_absent "a style rule leaves no template" "$BID"

# ---- restart 1: the rename comes back, alive ----
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
sleep 3
if grep -q "adopting existing window $AID" "$LOG"; then
    ok "the new instance adopted $AID"
else
    bad "$AID was not adopted after the restart"
fi
check_name "the rename survived the restart" "$AID" "п: рен старт"
check_tpl "...template still on the window" "$AID" "п: %t"
sendc 'wm title . {рен другой}'
wait_client "$LOG" 'рен другой'
check_name "...and %t is as live as before it" "$AID" "п: рен другой"
check_name "the style title came back as a STYLE" "$BID" "стиль: стильный сосед"
check_tpl_absent "...the restart invented no template" "$BID"
BLAYER=$(askw "info exists ::renameof($BDEC)")
if [ "$BLAYER" = "0" ]; then
    ok "...and no rename layer stands on the styled one"
else
    bad "the restart hung a rename layer on the styled window"
fi

# ---- the empty answer deletes the property... ----
rename_to "$AID" ''
check_name_absent "the emptied rename" "$AID"
check_tpl_absent "...took the template off the window" "$AID"

# ---- ...so the next restart resurrects nothing ----
"$LINUX/whale-cli" "$TOOLS/send-restart.tcl" "$DISPLAY"
sleep 3
check_name_absent "after the second restart" "$AID"
ALAYER=$(askw "info exists ::renameof($ADEC)")
if [ "$ALAYER" = "0" ]; then
    ok "...no rename layer rose from the dead"
else
    bad "the second restart resurrected a rename: [$ALAYER]"
fi

# ---- an ordinary withdraw sweeps both marks off the window ----
rename_to "$AID" 'w: %t'
check_name "a fresh rename before the withdraw" "$AID" "w: рен другой"
check_tpl "...with its template" "$AID" "w: %t"
sendc 'wm withdraw .'
check_tpl_absent "the withdraw swept the template" "$AID"
check_name_absent "...and the visible name" "$AID"

# ---- pre-naming: the template meets the FIRST manage ----
"$LINUX/whale" "$HERE/client-prename.tcl" > "$HERE/prename-c.log" 2>&1 &
CP=$!
_prename_said() { grep -q 'prename id:' "$HERE/prename-c.log"; }
wait_for 15 _prename_said
CID=$(sed -n 's/^prename id: //p' "$HERE/prename-c.log" | head -1)
xprop -id "$CID" -f _TK9WM_TITLE_TEMPLATE 8u \
    -set _TK9WM_TITLE_TEMPLATE 'pre: %t'
sendp 'wm deiconify .'
wait_client "$LOG" 'тихое окно'
check_name "the pre-set template named the window at manage" \
    "$CID" "pre: тихое окно"
PLAYER=$(askw "set ::renameof([expr {$CID + 0}])")
if [ "$PLAYER" = "pre: %t" ]; then
    ok "...and stands as the rename layer, verbatim"
else
    bad "the adopted layer says: «$PLAYER»"
fi

import -window root "$HERE/renamekeep-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/renamekeep-test.png"
kill $WM $CA $CB $CP 2>/dev/null

echo "--- verdict"
if grep -q 'soft failure\|handler error' "$LOG"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$LOG"; BAD=1
fi
LIVES=$(grep -c 'redirect armed' "$LOG")
if [ "$LIVES" = "3" ]; then
    ok "the log holds three lifetimes (two restarts, same fd)"
else
    bad "'redirect armed' seen $LIVES times, want 3"
fi
check_invariants "$LOG"
if grep -q 'WM: INVARIANT' "$LOG"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the name outlives the desk that was told it"
exit $BAD
