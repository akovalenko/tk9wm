#!/bin/sh
# Regression for the window surfaces that come and go by condition:
# winops-item rows and titlebar buttons under -needs/-when.
#
# One config declares three winops rows — unconditional, gated on a
# binary the machine lacks, gated on the window being an xterm — and
# two titlebar buttons under the same two gates; plus the stock rule
# in its new clothes: minimize-refuse is the minimize button's own
# -when now, and the refusing client must still lose the button.
#
# Presence is proved twice over: the wears-lines say what each frame
# was given, and the winops rows answer (or refuse to answer) their
# keys per window.
. "$(dirname "$0")/common.sh"
start_xvfb

key() { xdotool key "$@"; sleep 1; }
LOG="$HERE/wm-winopsitem.log"
askw() {
    printf '%s\n' "$1" > "$HERE/winopsitem-config/q.tcl"
    "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl \
        "$HERE/winopsitem-config/q.tcl" 2>&1
}

CONF="$HERE/winopsitem-config"
rm -rf "$CONF"; mkdir -p "$CONF"
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
proc Probe-Item {w} { puts "TEST: probe fired 0x[format %x $w]" }
winops-item probe {label проба key p command Probe-Item}
winops-item ghost {label дух command Probe-Item needs no-such-binary-xyzzy}
winops-item xonly {label только-икс key q command Probe-Item
                   when {filter -class XTerm}}
wm-style {filter -title "безмин*"} {minimize refuse}
titlebar-button hidden -side right -needs no-such-binary-xyzzy -glyph {<svg
 xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect x="4"
 y="4" width="8" height="8" stroke="#ffffff" fill="none"/></svg>}
titlebar-button xbadge -side right -when {filter -class XTerm} -glyph ?
wm-bind {<Super>r} Reload
EOF

XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "обычный-A" 200x100 "#fce94f" "" "" 90 \
    > "$HERE/woi-a.log" 2>&1 &
CA=$!
sleep 1
"$LINUX/whale" "$HERE/client.tcl" "безмин-B" 220x120 "#8ae234" "" "" 90 \
    > "$HERE/woi-b.log" 2>&1 &
CB=$!
sleep 1
xterm -T терм -e sleep 90 > "$HERE/woi-x.log" 2>&1 &
CX=$!
sleep 2

IDS=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
AID=$(echo "$IDS" | sed -n 1p)
BID=$(echo "$IDS" | sed -n 2p)
XID=$(echo "$IDS" | sed -n 3p)
wears_of() {
    f=$(sed -n "s/^WM: frame \(\.[a-z0-9]*\) for $1 .*/\1/p" "$LOG" | head -1)
    grep "^WM: frame $f wears" "$LOG" | head -1 | sed 's/^WM: frame [^ ]* //'
}

# ---- winops rows, on the xterm (focused: it mapped last) ----
key alt+space
key q                 # the xterm-only row answers here
key alt+space
key p                 # the unconditional row answers everywhere
key alt+space
key Escape
# ---- ...and on a window that is no xterm ----
key alt+Tab           # the quick toggle: back to безмин-B
key alt+space
key q                 # no such row here — nothing may fire
key p                 # the unconditional one still answers
# ---- the words survive a reload ----
key super+r
sleep 1
key alt+space
key p
sleep 1

# the text-glyph button must sit IN the row (the П-shaped rank was
# the owner's report) and INSIDE the stock trio (his order rule)
RANK=$(askw "set t \$::frameof([expr {$XID}])
    lassign [\$t.title item bbox 1 Cxbadge eBox] - ay1 - ay2
    lassign [\$t.title item bbox 1 Cclose eBox] - by1 - by2
    list top [expr {\$ay1 == \$by1}] bottom [expr {\$ay2 == \$by2}] \
        cols [lmap c [\$t.title column list] {lindex [\$t.title column cget \$c -tags] 0}]")
echo "--- rank: $RANK"

import -window root "$HERE/winopsitem-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/winopsitem-test.png"
kill $WM $CA $CB $CX 2>/dev/null

AW=$(wears_of "$AID"); BW=$(wears_of "$BID"); XW=$(wears_of "$XID")
FIRED=$(grep -c 'TEST: probe fired' "$LOG")
LASTID=$(sed -n 's/^TEST: probe fired \(0x[0-9a-f]*\)$/\1/p' "$LOG" | tail -1)
echo "--- A=$AID ($AW)"
echo "--- B=$BID ($BW)"
echo "--- X=$XID ($XW)"
echo "--- fired $FIRED times, last on $LASTID"
echo "--- WM saw:"
grep -E 'TEST:|winops: «|winops item' "$LOG" | head -12

echo "--- verdict"
BAD=0
if grep -q 'soft failure\|handler error' "$LOG"; then
    echo "FAIL: soft failures or handler errors:"
    grep 'soft failure\|handler error' "$LOG"; BAD=1
fi
case "$XW" in
    *xbadge*) echo "OK: the xterm's frame wears the -when button" ;;
    *) echo "FAIL: the xterm wears «$XW», no xbadge"; BAD=1 ;;
esac
case "$AW" in
    *xbadge*) echo "FAIL: a non-xterm wears the -when button: $AW"; BAD=1 ;;
    *) echo "OK: a non-xterm does not wear it" ;;
esac
case "$AW$BW$XW" in
    *hidden*) echo "FAIL: the -needs button appeared without its binary"; BAD=1 ;;
    *) echo "OK: the -needs button exists on no frame — the machine lacks it" ;;
esac
case "$BW" in
    *minimize*) echo "FAIL: the refusing client still wears minimize: $BW"; BAD=1 ;;
    *) echo "OK: minimize-refuse still costs the button — through -when now" ;;
esac
case "$AW" in
    *minimize*) echo "OK: ...and an ordinary client keeps it" ;;
    *) echo "FAIL: the ordinary client lost minimize: $AW"; BAD=1 ;;
esac
if grep -q 'WM: winops: «ghost» waits on no-such-binary-xyzzy' "$LOG"; then
    echo "OK: the needs-gated row says why it is not shown"
else
    echo "FAIL: the ghost row vanished silently"; BAD=1
fi
if [ "$RANK" = "top 1 bottom 1 cols {Cmenu C0 Cxbadge Cminimize Cmaximize Cclose}" ]; then
    echo "OK: the ? button sits square in the row, inside the stock trio"
else
    echo "FAIL: the button rank says: $RANK"; BAD=1
fi
if [ "$FIRED" = "4" ] && [ "$LASTID" = "$BID" ]; then
    echo "OK: q answered on the xterm alone, p everywhere, and the reload kept the rows"
else
    echo "FAIL: fired $FIRED times (want 4), last on $LASTID (want $BID)"; BAD=1
fi

check_invariants "$LOG"
if grep -q 'WM: INVARIANT' "$LOG"; then BAD=1; fi

[ $BAD -eq 0 ] && echo "OK: the window's surfaces come and go by machine and by window"
exit $BAD
