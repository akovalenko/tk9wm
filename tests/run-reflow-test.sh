#!/bin/sh
# Regression for the workarea reflow: when the workarea moves under the
# windows, the windows follow it (the owner's wish, 2026-07-30 — "at the
# very least, whatever was stuck to the old border re-sticks to the new
# one, and whatever arithmetically looks maximized goes to the new
# maximization").
#
# The desk is driven through THREE live reloads on one WM, because what
# matters about a reflow is which of the four per-axis cases a window
# falls into, and the panel is the cheapest way to move a workarea in
# every way it can move:
#
#   bottom -> top    the origin moves, the extent does not (a pure move)
#   top    -> right  the FAR edge moves, on the other axis, and the
#                    extents change with it (a re-fit)
#   right  -> left   with follow OFF: the workarea moves both ways at
#                    once and nothing may move at all
#
# The cast is one window per case, all placed BY RULE so that the run
# does not depend on a click landing anywhere. Every rule says `force`:
# a Tk client's `wm geometry` claims a position (USPosition, always —
# measured 2026-07-30), and a place yields to a claim unless it insists.
#
#   stolb     `place top`             spans X, flush at the near Y edge
#   ugol      `place {bottom right}`  flush at BOTH far edges
#   seredina  `place 40%center`       flush at nothing — must NOT move
#   terminal  an xterm, `place max`   spans both, and its increments mean
#                                     it does NOT reach the far edges —
#                                     the case that fails outright if the
#                                     span test compares raw extents
#   maksugol  `place {bottom right}`, then maximized by the chord: spans
#             both, and its SAVED geometry is flush at both far edges, so
#             the way back has to travel too — measured by unmaximizing
#             it at the end.
#   setka     a GRIDDED client (inc 10x10) standing six pixels short of
#             both far edges — which is what "flush" means for a window
#             whose size is quantized, and the case the owner reported
#             (2026-07-30: on a panel change his browsers re-stuck and
#             xterm and emacs sat where they were). It cannot be placed
#             by rule: a placement lands its pinned edge exactly, so
#             this one claims its own position and the shell works out
#             the arithmetic from the published workarea.
. "$(dirname "$0")/common.sh"
export DISPLAY=:55
rm -f /tmp/.X55-lock /tmp/.X11-unix/X55
Xvfb :55 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
CONF=$(mktemp -d)
CLIENTS=""
trap 'kill $XVFB $CLIENTS 2>/dev/null; rm -rf "$CONF"' EXIT
sleep 1

RULES='wm-style {filter -title stolb}    {place {top force}}
wm-style {filter -title ugol}     {place {bottom right force}}
wm-style {filter -title maksugol} {place {bottom right force}}
wm-style {filter -title seredina} {place {40%center force}}
wm-style {filter -title terminal} {place {max force}}
panel-button один { launch {} }'

conf() {   # conf SIDE ?extra-line?
    { echo "set-panel-side $1"; echo "$RULES"
      [ -n "$2" ] && echo "$2"; } > "$CONF/tk9wm.tcl"
}
conf bottom

LOG="$HERE/wm-reflow.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
sleep 1.5

tkclient() {
    "$LINUX/whale" "$HERE/client.tcl" "$1" "$2" "$3" "" "" 120 &
    CLIENTS="$CLIENTS $!"; sleep 1.2
}
tkclient stolb    300x150 "#8ae234"
tkclient ugol     240x120 "#729fcf"
tkclient seredina 200x100 "#ad7fa8"
xterm -T terminal -e sleep 120 >/dev/null 2>&1 &
CLIENTS="$CLIENTS $!"; sleep 1.5
tkclient maksugol 240x120 "#fce94f"
sleep 1

set -- $(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG")
STOLB=$1; UGOL=$2; SEREDINA=$3; TERM=$4; MAKS=$5
eval "$(sed -n 's/^WM: titlebar h=\([0-9]*\) top=\([0-9]*\).*/TITLEH=\1; TOP=\2/p' \
        "$LOG" | head -1)"
B=$((TOP - TITLEH - 2))
echo "--- cast: stolb=$STOLB ugol=$UGOL seredina=$SEREDINA terminal=$TERM\
 maksugol=$MAKS (border $B, deco top $TOP)"

# The FRAME's rectangle, which is what is flush with an edge or fills a
# workarea — xwininfo can only be asked about the client inside it.
fx() { xwininfo -id "$1" | awk -v b="$B" '/Absolute upper-left X/ {print $NF - b}'; }
fy() { xwininfo -id "$1" | awk -v t="$TOP" '/Absolute upper-left Y/ {print $NF - t}'; }
fw() { xwininfo -id "$1" | awk -v b="$B" '/Width:/ {print $2 + 2*b}'; }
fh() { xwininfo -id "$1" | awk -v t="$TOP" -v b="$B" '/Height:/ {print $2 + t + b}'; }
right()  { echo $(( $(fx "$1") + $(fw "$1") )); }
bottom() { echo $(( $(fy "$1") + $(fh "$1") )); }
rect()   { echo "$(fw "$1")x$(fh "$1")+$(fx "$1")+$(fy "$1")"; }
size()   { echo "$(fw "$1")x$(fh "$1")"; }
# The workarea as the WM publishes it, which is the rect every
# expectation below is stated against: the panel's thickness is the
# font's business, and differs between a row and a column anyway.
wa() {
    xprop -root _NET_WORKAREA | sed 's/.*= //; s/,//g' \
        | awk '{print "WAX=" $1 "; WAY=" $2 "; WAW=" $3 "; WAH=" $4}'
}
reload() { "$LINUX/whale-cli" "$TOOLS/send-reload.tcl" :55 >/dev/null 2>&1; sleep 1.5; }
reflows() { grep -c 'WM: reflow' "$LOG"; }
# Focus the window a chord is meant for by clicking its titlebar, so the
# run does not depend on who happens to have focus after a reload.
chord() {   # chord CLIENT-ID KEY
    xdotool mousemove $(( $(fx "$1") + 40 )) \
                      $(( $(fy "$1") + B + TITLEH / 2 )) click 1
    sleep 0.4
    xdotool key alt+space; sleep 0.4; xdotool key "$2"; sleep 0.8
}

MAKS_SIZE=$(size "$MAKS")     # what the way back must come back to
chord "$MAKS" x               # ...and it is maximized from here on
eval "$(wa)"

# The gridded one, six pixels short of both far edges. A position claim
# with the usual NorthWest gravity places the FRAME (measured here, and
# the reading step 62 settled), so the arithmetic is the frame's: 300x200
# of client plus the border on both sides and the strip on top.
SHORT=6
GX=$((WAX + WAW - SHORT - 300 - 2 * B))
GY=$((WAY + WAH - SHORT - 200 - TOP - B))
"$LINUX/whale" "$HERE/client-grid.tcl" setka "#e9b96e" "+$GX+$GY" 120 &
CLIENTS="$CLIENTS $!"; sleep 1.5
SETKA=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | tail -1)
SR=$(right "$SETKA");  A_SETKA_SHORT_R=$((WAX + WAW - SR))
SB=$(bottom "$SETKA"); A_SETKA_SHORT_B=$((WAY + WAH - SB))
echo "    setka $(rect "$SETKA") — short by $A_SETKA_SHORT_R/$A_SETKA_SHORT_B"
A_SEREDINA=$(rect "$SEREDINA"); A_TERM_W=$(fw "$TERM")
echo "--- pass A (panel bottom), workarea ${WAW}x${WAH}+${WAX}+${WAY}"
echo "    stolb $(rect "$STOLB")  ugol $(rect "$UGOL")  seredina $A_SEREDINA"
echo "    terminal $(rect "$TERM")  maksugol $(rect "$MAKS") (was $MAKS_SIZE)"

# --- pass B: the panel moves to the top. The origin moves by its
# thickness and the extent is the same, so nothing needs re-fitting and
# everything needs moving.
conf top; reload
eval "$(wa)"; B_WAY=$WAY; B_WAH=$WAH; B_WAW=$WAW
B_STOLB_Y=$(fy "$STOLB"); B_STOLB_W=$(fw "$STOLB")
B_UGOL_BOTTOM=$(bottom "$UGOL"); B_UGOL_RIGHT=$(right "$UGOL")
B_SEREDINA=$(rect "$SEREDINA")
B_MAKS_X=$(fx "$MAKS"); B_MAKS_Y=$(fy "$MAKS"); B_TERM_Y=$(fy "$TERM")
SB=$(bottom "$SETKA"); B_SETKA_SHORT_B=$((WAY + WAH - SB))
SR=$(right "$SETKA");  B_SETKA_SHORT_R=$((WAX + WAW - SR))
echo "--- pass B (panel top), workarea ${WAW}x${WAH}+${WAX}+${WAY}"
echo "    stolb $(rect "$STOLB")  ugol $(rect "$UGOL")  seredina $B_SEREDINA"
echo "    terminal $(rect "$TERM")  maksugol $(rect "$MAKS")"

# --- pass C: the panel moves to the RIGHT edge. Now it is the FAR edge
# of the other axis that moves, and the extents change with it — the
# pass where a spanning window has to be re-fitted and not merely
# carried, and where a window flush at the far edge has somewhere to go.
conf right; reload
eval "$(wa)"; C_WAX=$WAX; C_WAY=$WAY; C_WAW=$WAW; C_WAH=$WAH
C_STOLB_X=$(fx "$STOLB"); C_STOLB_W=$(fw "$STOLB"); C_STOLB_Y=$(fy "$STOLB")
C_UGOL_RIGHT=$(right "$UGOL"); C_UGOL_BOTTOM=$(bottom "$UGOL")
C_SEREDINA=$(rect "$SEREDINA")
C_TERM_X=$(fx "$TERM"); C_TERM_W=$(fw "$TERM"); C_TERM_RIGHT=$(right "$TERM")
C_MAKS_X=$(fx "$MAKS"); C_MAKS_W=$(fw "$MAKS")
SR=$(right "$SETKA");  C_SETKA_SHORT_R=$((WAX + WAW - SR))
C_SETKA_SIZE=$(size "$SETKA")
echo "--- pass C (panel right), workarea ${WAW}x${WAH}+${WAX}+${WAY}"
echo "    stolb $(rect "$STOLB")  ugol $(rect "$UGOL")  seredina $C_SEREDINA"
echo "    terminal $(rect "$TERM")  maksugol $(rect "$MAKS")"

# The way back: the saved geometry was flush at both far edges of the
# workarea in pass A, and both of those edges have moved twice since.
chord "$MAKS" x
UNMAX_RIGHT=$(right "$MAKS"); UNMAX_BOTTOM=$(bottom "$MAKS")
UNMAX_SIZE=$(size "$MAKS")
echo "--- unmaximized to $(rect "$MAKS")"

# --- pass D: follow off, and the panel to the LEFT edge — a workarea
# that moves its origin AND its extent at once. Nothing may move, which
# is what every version before the reflow did.
N_BEFORE=$(reflows)
conf left 'set-workarea-follow off'; reload
eval "$(wa)"
D_STOLB="$(fx "$STOLB") $(fw "$STOLB")"; D_UGOL=$(right "$UGOL")
N_AFTER=$(reflows)
echo "--- pass D (follow off, panel left), workarea ${WAW}x${WAH}+${WAX}+${WAY}"

kill $WM $CLIENTS 2>/dev/null

echo "--- workarea and reflow lines:"
grep -E 'WM: workarea |WM: reflow ' "$LOG" | sed 's/^/    /'

echo "--- verdict"
if grep -q 'BadAccess request=2' "$LOG"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
expect() {   # what wanted got
    if [ "$2" = "$3" ]; then echo "OK: $1 ($3)"
    else echo "FAIL: $1 — wanted $2, got $3"; fi
}
atmost() {   # what limit got
    if [ "$3" -le "$2" ]; then echo "OK: $1 ($3 <= $2)"
    else echo "FAIL: $1 — wanted at most $2, got $3"; fi
}
has() {      # what pattern
    if grep -q "$2" "$LOG"; then echo "OK: $1"
    else echo "FAIL: $1 — no «$2» in the log"; fi
}

# pass B — the origin moved, the extent did not
expect "the column follows the origin down to the new top edge" \
    "$B_WAY" "$B_STOLB_Y"
expect "...and keeps the width it spanned, the extent being unchanged" \
    "$B_WAW" "$B_STOLB_W"
expect "the corner window re-sticks to the new bottom edge" \
    "$((B_WAY + B_WAH))" "$B_UGOL_BOTTOM"
expect "...and its right edge, whose far edge did not move, stays put" \
    "800" "$B_UGOL_RIGHT"
expect "the maximized window moves to the new origin" \
    "0 $B_WAY" "$B_MAKS_X $B_MAKS_Y"
expect "the xterm too, increments and all" "$B_WAY" "$B_TERM_Y"
expect "the gridded window, six short of the bottom, is six short of the new one" \
    "$A_SETKA_SHORT_B" "$B_SETKA_SHORT_B"
expect "...and its right edge, whose far edge did not move, is unchanged" \
    "$A_SETKA_SHORT_R" "$B_SETKA_SHORT_R"
expect "the window flush with nothing does not move" "$A_SEREDINA" "$B_SEREDINA"
has "the substrate said the workarea changed" 'WM: workarea 0 0 800'
has "and the reflow named the case it found: span/near for the column" \
    "WM: reflow $STOLB span/near"
has "...far/far for the corner window" "WM: reflow $UGOL far/far"
has "...span/span for the maximized one" "WM: reflow $MAKS span/span"

# pass C — the extent changed, so a spanning window must be RE-FITTED
expect "the column spans the narrowed workarea" \
    "$C_WAX $C_WAW" "$C_STOLB_X $C_STOLB_W"
expect "...and is back at the top edge, which moved back to 0" \
    "$C_WAY" "$C_STOLB_Y"
expect "the corner window re-sticks to the new right edge" \
    "$((C_WAX + C_WAW))" "$C_UGOL_RIGHT"
expect "...and stays on the bottom edge, which did not move" \
    "$((C_WAY + C_WAH))" "$C_UGOL_BOTTOM"
expect "the maximized window re-fits to the narrowed workarea" \
    "$C_WAX $C_WAW" "$C_MAKS_X $C_MAKS_W"
expect "the still-untouched window is still untouched" "$A_SEREDINA" "$C_SEREDINA"
# The xterm is the one that cannot be checked for equality: its size is
# whole cells and the slack sits at the far edge. What must hold is that
# it was RE-FITTED and not merely carried — carried, it would keep its
# old width and hang over the new right edge by the panel's thickness.
expect "the xterm sits flush against the near edge" "$C_WAX" "$C_TERM_X"
atmost "...and its right edge is inside the narrowed workarea" \
    "$((C_WAX + C_WAW))" "$C_TERM_RIGHT"
if [ "$C_TERM_W" -lt "$A_TERM_W" ]; then
    echo "OK: the xterm was re-fitted, not carried ($A_TERM_W -> $C_TERM_W wide)"
else
    echo "FAIL: the xterm kept its old width ($A_TERM_W -> $C_TERM_W)"
fi

# the way back travelled with the window
expect "unmaximizing lands on the CURRENT far edges, not the saved ones" \
    "$((C_WAX + C_WAW)) $((C_WAY + C_WAH))" "$UNMAX_RIGHT $UNMAX_BOTTOM"
expect "...at the size that was saved" "$MAKS_SIZE" "$UNMAX_SIZE"

# pass D — the knob
expect "follow off moves nothing" "$N_BEFORE" "$N_AFTER"
expect "...so the column stays as wide and where the last reflow left it" \
    "$C_STOLB_X $C_STOLB_W" "$D_STOLB"
expect "...and the corner window keeps hanging over the new strip" \
    "$C_UGOL_RIGHT" "$D_UGOL"

if grep -q 'handler error' "$LOG"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$LOG"
fi
if grep -q 'soft failure' "$LOG"; then
    echo "FAIL: soft failures present:"; grep 'soft failure' "$LOG" | sort -u
fi
check_invariants "$LOG"
