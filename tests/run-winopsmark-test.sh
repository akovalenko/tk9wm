#!/bin/sh
# Regression for the winops state markers: a row whose verb is a
# toggle wears a bullet while the state holds. The marker is a fact
# about the VERB (command-state), so the stock rows and a config's own
# row are marked by one mechanism; the menu reads the state at open.
#
# Driven through the states one by one: maximized_vert alone marks the
# axis row and NOT the full Maximize (the toggle's own reading — any
# axis free means maximize); both atoms mark the trio; fullscreen,
# Above and Sticky mark their rows; a config verb declared with
# command-state marks and unmarks as its state flips; a predicate that
# throws is logged and reads unmarked without costing the menu; the
# declaration survives a reload; and Minimize's predicate answers for
# the iconified window even though no menu opens over one yet.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1; }
LOG="$HERE/wm-winopsmark.log"
CONF="$HERE/winopsmark-config"
askw() {
    printf '%s\n' "$1" > "$CONF/q.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl" 2>&1
}
marks_of() {
    askw 'set out {}
foreach i [.winops.t item children root] {
    if {[.winops.t item element cget $i Cmark eMark -text] ne ""} {
        lappend out [.winops.t item element cget $i C0 eTxt -text]
    }
}
join $out ,'
}
labels_of() {
    askw 'join [lmap i [.winops.t item children root] {
    .winops.t item element cget $i C0 eTxt -text
}] ,'
}

rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
proc Probe-Toggle {w} {
    if {[info exists ::probe_on($w)]} { unset ::probe_on($w) } \
    else { set ::probe_on($w) 1 }
    puts "TEST: probe now [info exists ::probe_on($w)] 0x[format %x $w]"
}
proc probe-on-p {w} { info exists ::probe_on($w) }
winops-item probe {label проба key p command Probe-Toggle}
command-state Probe-Toggle probe-on-p
proc Broke-It {w} {}
winops-item broke {label сломан command Broke-It}
command-state Broke-It no-such-proc
wm-bind {<Super>r} Reload
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM

"$LINUX/whale" "$HERE/client.tcl" "жертва" 240x120 "#8ae234" "" "" 90 \
    > "$HERE/wmark-a.log" 2>&1 &
CA=$!
wait_client "$LOG" 'жертва'
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | head -1)

# ---- a plain window: rows in order, nothing marked ----
key alt+space
LABELS=$(labels_of)
MARKS0=$(marks_of)
key Escape

# ---- one axis held marks the axis row alone ----
wmctrl -i -r "$AID" -b add,maximized_vert; sleep 1
key alt+space
MARKS_V=$(marks_of)
key Escape

# ---- both axes mark the trio ----
wmctrl -i -r "$AID" -b add,maximized_horz; sleep 1
key alt+space
MARKS_HV=$(marks_of)
key Escape

# ---- fullscreen marks its row (the menu opens over fullscreen) ----
wmctrl -i -r "$AID" -b add,fullscreen; sleep 1
key alt+space
MARKS_FS=$(marks_of)
key Escape
wmctrl -i -r "$AID" -b remove,fullscreen; sleep 1

# ---- Sticky and Above by their own menu keys, read back marked ----
key alt+space
key y
key alt+space
key a
key alt+space
MARKS_AY=$(marks_of)
key Escape

# ---- the config's own verb: марка ходит за его состоянием ----
key alt+space
key p
key alt+space
MARKS_P1=$(marks_of)
key Escape
key alt+space
key p
key alt+space
MARKS_P0=$(marks_of)
key Escape

# ---- the declaration survives a reload ----
key super+r
sleep 1
key alt+space
key p
key alt+space
MARKS_R=$(marks_of)
key Escape

# ---- Minimize: the predicate answers though no menu opens there yet ----
key alt+space
key i
ICONIC=$(askw "list [iconic-p [expr {$AID}]] [command-marked-p Minimize [expr {$AID}]]")

import -window root "$HERE/winopsmark-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/winopsmark-test.png"
kill $WM $CA 2>/dev/null

STOCK="Maximize,Maximize-V,Maximize-H,Fullscreen,Close,Destroy,Raise,Lower,Bury,Move,Resize,Minimize,Above,Sticky"
TRIO="Maximize,Maximize-V,Maximize-H"
echo "--- A=$AID"
echo "--- labels: $LABELS"
echo "--- marks: 0=«$MARKS0» V=«$MARKS_V» HV=«$MARKS_HV» FS=«$MARKS_FS»"
echo "---        AY=«$MARKS_AY» P1=«$MARKS_P1» P0=«$MARKS_P0» R=«$MARKS_R»"
echo "--- iconic: $ICONIC"
echo "--- WM saw:"
grep -E 'TEST:|command-state' "$LOG" | head -8

echo "--- verdict"
BAD=0
if grep -q 'soft failure\|handler error' "$LOG"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$LOG"; BAD=1
fi
if [ "$LABELS" = "$STOCK,проба,сломан" ]; then
    echo "OK: the stock rows carry the axis pair, the config's rows follow"
else
    echo "FAIL: the menu reads: $LABELS"; BAD=1
fi
if [ "$MARKS0" = "" ]; then
    echo "OK: a plain window marks nothing"
else
    echo "FAIL: a plain window marks: $MARKS0"; BAD=1
fi
if [ "$MARKS_V" = "Maximize-V" ]; then
    echo "OK: one held axis marks its own row and not the full Maximize"
else
    echo "FAIL: with vert alone the marks are «$MARKS_V», want Maximize-V"; BAD=1
fi
if [ "$MARKS_HV" = "$TRIO" ]; then
    echo "OK: both axes mark the trio"
else
    echo "FAIL: with both axes the marks are «$MARKS_HV», want $TRIO"; BAD=1
fi
if [ "$MARKS_FS" = "$TRIO,Fullscreen" ]; then
    echo "OK: fullscreen marks its row, and the menu opened over it"
else
    echo "FAIL: fullscreen marks are «$MARKS_FS», want $TRIO,Fullscreen"; BAD=1
fi
if [ "$MARKS_AY" = "$TRIO,Above,Sticky" ]; then
    echo "OK: Above and Sticky mark after their own menu keys"
else
    echo "FAIL: above+sticky marks are «$MARKS_AY», want $TRIO,Above,Sticky"; BAD=1
fi
if [ "$MARKS_P1" = "$TRIO,Above,Sticky,проба" ] \
        && [ "$MARKS_P0" = "$TRIO,Above,Sticky" ]; then
    echo "OK: command-state marks the config's own verb and lets it go"
else
    echo "FAIL: probe marks on=«$MARKS_P1» off=«$MARKS_P0»"; BAD=1
fi
case "$MARKS_R" in
    *проба*) echo "OK: the declaration survived the reload" ;;
    *) echo "FAIL: after reload the marks are «$MARKS_R», no проба"; BAD=1 ;;
esac
if grep -q 'WM: command-state «Broke-It»: predicate error' "$LOG"; then
    echo "OK: a throwing predicate is logged and costs nothing"
else
    echo "FAIL: no log line for the broken predicate"; BAD=1
fi
if [ "$ICONIC" = "1 1" ]; then
    echo "OK: Minimize answers for the iconified window (surface pending)"
else
    echo "FAIL: iconic answers: $ICONIC (want «1 1»)"; BAD=1
fi

check_invariants "$LOG"
if grep -q 'WM: INVARIANT' "$LOG"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the menu tells the window's state, verb by verb"
exit $BAD
