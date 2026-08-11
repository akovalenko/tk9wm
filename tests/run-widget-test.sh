#!/bin/sh
# Regression for WIDGETS — the desk's own furniture — on the clock,
# which is the first of them, and for the FONT HIERARCHY it is set in.
#
# The owner's requirements (2026-07-30), each one measured:
#
#  - a widget is AGNOSTIC about where it lives: the same declaration
#    with one option changed puts it on a panel or on the desk;
#  - the strip HANDS OUT the slot — the widget area sits at the far end
#    of a panel BEFORE the tray, which is the bug that started this
#    (his clock, placing itself by its own corner, sat under the tray);
#  - the desk is ONE window of ours, and switching it off gives every
#    desk-layer area a toplevel again — the fallback for a desktop
#    somebody else paints;
#  - the clock is bigger than the date and both DERIVE from the desk
#    font, so moving the desk font moves them, with nothing edited;
#  - widgets are CHEAP: a reload destroys and rebuilds them.
#
# Everything is measured on the SCREEN, because a contained widget has
# no window of its own to find — which is the point of containing it.
. "$(dirname "$0")/common.sh"
start_xvfb 900x500x24
CONF=$(mktemp -d)
trap 'stop_xservers; rm -rf "$CONF"' EXIT
# A colour of its own, so a pixel can say "the clock is here" without
# arguing with the panel's background.
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
set-tray on
action терминал { launch {exec xterm &} }
panel-button терминал
wm-widget clock -type clock -on {panel default} -background #4e9a06
EOF
sleep 1

LOG="$HERE/wm-widget.log"
XDG_CONFIG_HOME="$CONF" "$LINUX/whale" "$WMTCL" > "$LOG" 2>&1 &
WM=$!
wait_wm "$LOG" $WM
"$LINUX/whale" "$HERE/tray-client.tcl" "#729fcf" > "$HERE/widget-tray.log" &
TRAY=$!
sleep 2

area() { sed -n 's/^WM: widget area //p' "$LOG" | tail -1; }
# The colour at the middle of a WxH+X+Y rectangle.
here() {
    set -- $(echo "$1" | sed 's/[x+]/ /g')
    [ $# -ge 4 ] || { echo "(no geometry)"; return; }
    import -window root png:- 2>/dev/null | convert png:- -format \
        "%[pixel:p{$(($3 + $1 / 2)),$(($4 + $2 / 2))}]" info:-
}
traygeom() { sed -n 's/^WM: tray strip \([0-9x+]*\) .*/\1/p' "$LOG" | tail -1; }

ON_PANEL=$(area)
PANELPX=$(here "$(echo "$ON_PANEL" | sed 's/ .*//')")
TRAYG=$(traygeom)
# The panel's WINDOW against the band it reserved: a strip that grew
# for a passenger and left the growth to nobody is a stripe of nothing
# along its top, with the passenger hanging out of the bottom (the
# owner, 2026-07-30). The window must be the whole band.
PANELG=$(sed -n 's/^WM: panel default up (.*, \([0-9x+]*\))$/\1/p' "$LOG" | tail -1)
PANELH=$(echo "$PANELG" | sed 's/^[0-9]*x\([0-9]*\)+.*/\1/')
BANDH=$(echo "$ON_PANEL" | sed 's/^[0-9]*x\([0-9]*\)+.*/\1/')
import -display "$DISPLAY" -window root "$HERE/widget-panel.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/widget-panel.png"

# --- a client raised over the desk, then a reload: containment means
#     the widget cannot be lost behind anything.
"$LINUX/whale" "$HERE/client.tcl" "поверх" 400x200 "#fce94f" "" "" 30 \
    > "$HERE/widget-client.log" &
CL=$!
wait_client "$LOG" 'поверх'
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
sleep 1.5
STILLPX=$(here "$(area | sed 's/ .*//')")
kill $CL 2>/dev/null
sleep 0.5

# --- the same widget, told to live on the desk instead
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
action терминал { launch {exec xterm &} }
panel-button терминал
wm-widget clock -type clock -on screen -place {left top} -background #4e9a06
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
sleep 1.5
ON_DESK=$(area)
DESKPX=$(here "$(echo "$ON_DESK" | sed 's/ .*//')")
DESKWIN=$(xdotool search --onlyvisible --name '^tk9wm-desk$' | head -1)

# --- and with the desk window switched off it falls back to a toplevel
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
set-desk-window off
action терминал { launch {exec xterm &} }
panel-button терминал
wm-widget clock -type clock -on screen -place {left top} -background #4e9a06
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
sleep 1.5
NODESK=$(xdotool search --onlyvisible --name '^tk9wm-desk$' | head -1)
OWNWIN=$(xdotool search --onlyvisible --name '^tk9wm-widget-area' | head -1)
OFFPX=$(here "$(area | sed 's/ .*//')")

# --- a bigger desk font must carry both lines with it
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
set-desk-font -size 20
action терминал { launch {exec xterm &} }
panel-button терминал
wm-widget clock -type clock -on screen -place {left top} -background #4e9a06
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
sleep 1.5
BIG=$(area)
import -display "$DISPLAY" -window root "$HERE/widget-desk.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/widget-desk.png"

# --- the clock's faces are the desk's knobs (widget-params, step B):
# declared with the type, they stand in the fonts group; a set
# re-derives the face on the spot and the widget rebuilds for it; and
# a face already written into the kin survives the declaration running
# again (keep-fashion — the re-source case).
q() { printf '%s\n' "$1" > "$CONF/q.tcl"
      "$LINUX/whale" "$TOOLS/send-eval.tcl" tk9wm.tcl "$CONF/q.tcl"; }
FONTKNOB=$(q 'set m [dict get [knob-registry] set-clock-font]
    set was [font configure ClockFont -size]
    set-clock-font -size 2.5x
    update
    widget-type-font clock ClockFont {default {-size 1.6x -weight bold}}
    list kind [dict get $m kind] group [dict get $m group] \
         grew [expr {abs([font configure ClockFont -size]) > abs($was)}] \
         kept [dict get $::font_kin ClockFont opts] \
         kin [llength [info commands set-desk-num-font]]')
sleep 1.5
FONTAREA=$(area)

# --- a clock told a ZONE tells the zone's time, wears its tiny label,
#     and a zone alone glues NO label on (the owner, 2026-08-11): the
#     naming word is only ever SAID. Two clocks, one strip: «туда» is
#     zoned and named, «тихо» is zoned and mute.
cat > "$CONF/tk9wm.tcl" <<'EOF'
set-welcome off
action терминал { launch {exec xterm &} }
panel-button терминал
wm-widget туда -type clock -on {panel default} \
    -timezone Pacific/Auckland -label ОКЛ
wm-widget тихо -type clock -on {panel default} -timezone Pacific/Auckland
EOF
"$LINUX/whale-cli" "$TOOLS/send-reload.tcl" "$DISPLAY" >/dev/null 2>&1
sleep 1.5
# The minute may roll between the widget's tick and the reading here,
# so the answer a beat ago is accepted too.
ZONED=$(q 'widget-tick-once туда
    set c $::widget_win(туда)
    set n [clock seconds]
    set want [clock format $n -format %H:%M -timezone Pacific/Auckland]
    set ago [clock format [expr {$n - 60}] -format %H:%M \
                 -timezone Pacific/Auckland]
    set got [$c.time cget -text]
    list zone [expr {$got eq $want || $got eq $ago}] \
         label [$c.label cget -text] \
         shown [winfo ismapped $c.label] \
         mute [winfo ismapped $::widget_win(тихо).label] \
         small [expr {[font metrics ClockLabelFont -linespace] \
                          < [font metrics DateFont -linespace]}]')

# --- ONE heartbeat per widget, however many rebuilds: the beat's
#     script is its own name (after cancel by the very words `after`
#     took), so a rebuild supersedes the pending chain instead of
#     stacking one more beside it — the owner's after queue held
#     eight per widget, one per rebuild (2026-08-11).
BEATS=$(q 'widgets-build; widgets-build; widgets-build
    set n {}
    foreach w {туда тихо} {
        set c 0
        foreach id [after info] {
            if {[lindex [after info $id] 0] eq [list widget-tick $w]} {
                incr c
            }
        }
        lappend n $w $c
    }
    set n')

kill $WM $TRAY 2>/dev/null

echo "--- areas:"
grep -E '^WM: widget area ' "$LOG"
echo "--- on the panel: $ON_PANEL (tray at $TRAYG)"
echo "--- on the desk:  $ON_DESK   with a big font: $BIG"

echo "--- verdict"
FAIL=0
case "$ON_PANEL" in
    *"in the «default» panel, before the tray"*)
        echo "OK: the strip handed out the slot ($ON_PANEL)" ;;
    *) echo "FAIL: the widget did not land in the panel's slot: «$ON_PANEL»"
       FAIL=1 ;;
esac
# ...and BEFORE the tray means its right edge is left of the tray's.
AR=$(echo "$ON_PANEL" | sed 's/x.*//')
AX=$(echo "$ON_PANEL" | sed 's/^[0-9]*x[0-9]*+\([0-9]*\)+.*/\1/')
TX=$(echo "$TRAYG" | sed 's/^[0-9]*x[0-9]*+\([0-9]*\)+.*/\1/')
if [ -n "$AX" ] && [ -n "$TX" ] && [ $((AX + AR)) -le "$TX" ]; then
    echo "OK: ...clear of the tray — it ends at $((AX + AR)), the tray starts\
 at $TX"
else
    echo "FAIL: the widget ends at $((AX + AR)) and the tray starts at $TX —\
 that is the bug that started this"; FAIL=1
fi
if [ -n "$PANELH" ] && [ -n "$BANDH" ] && [ "$PANELH" -ge "$BANDH" ]; then
    echo "OK: ...and the panel's window covers it — ${PANELH}px of strip for a\
 ${BANDH}px passenger, no stripe of nothing above it"
else
    echo "FAIL: the panel window is ${PANELH}px and its passenger ${BANDH}px —\
 the strip grew and the window did not"; FAIL=1
fi
if [ "$PANELPX" = "srgb(78,154,6)" ]; then
    echo "OK: ...and it is DRAWN there, its own colour on the screen"
else
    echo "FAIL: nothing of the widget at its own coordinates ($PANELPX)"; FAIL=1
fi
if [ "$STILLPX" = "srgb(78,154,6)" ]; then
    echo "OK: ...and still is after a client was raised and the config\
 reloaded — inside the panel, it has no layer to lose"
else
    echo "FAIL: the widget went behind something ($STILLPX)"; FAIL=1
fi
case "$ON_DESK" in
    *"on the desk over screen at «left top»"*)
        echo "OK: one option changed and it lives on the desk instead" ;;
    *) echo "FAIL: told -on screen it went «$ON_DESK»"; FAIL=1 ;;
esac
if [ -n "$DESKWIN" ] && [ "$DESKPX" = "srgb(78,154,6)" ]; then
    echo "OK: ...inside the desk window, which is ours and one (id $DESKWIN)"
else
    echo "FAIL: desk window «$DESKWIN», pixel $DESKPX"; FAIL=1
fi
if [ -z "$NODESK" ] && [ -n "$OWNWIN" ] && [ "$OFFPX" = "srgb(78,154,6)" ]; then
    echo "OK: set-desk-window off — no desk window, and the area fell back to\
 a toplevel of its own (id $OWNWIN), still drawn"
else
    echo "FAIL: with the desk window off: desk «$NODESK», own «$OWNWIN»,\
 pixel $OFFPX"; FAIL=1
fi
BIGW=$(echo "$BIG" | sed 's/x.*//')
SMALLW=$(echo "$ON_DESK" | sed 's/x.*//')
if [ -n "$BIGW" ] && [ -n "$SMALLW" ] && [ "$BIGW" -gt "$SMALLW" ]; then
    echo "OK: a bigger DESK font carried the clock with it ($SMALLW -> $BIGW px\
 wide), nothing about the widget edited"
else
    echo "FAIL: the desk font grew and the clock did not ($SMALLW -> $BIGW)"
    FAIL=1
fi
echo "--- font knob: $FONTKNOB  area after set-clock-font: $FONTAREA"
if [ "$FONTKNOB" = "kind {font ClockFont} group fonts grew 1 kept {-size 2.5x} kin 1" ]; then
    echo "OK: the clock's face is a knob — declared with the type, re-derived\
 on set, and the kin keeps a written word over the declaration's default"
else
    echo "FAIL: the font knob answered {$FONTKNOB}"; FAIL=1
fi
FONTW=$(echo "$FONTAREA" | sed 's/x.*//')
if [ -n "$FONTW" ] && [ -n "$BIGW" ] && [ "$FONTW" -gt "$BIGW" ]; then
    echo "OK: ...and the widget rebuilt wider for it ($BIGW -> $FONTW px)"
else
    echo "FAIL: set-clock-font did not rebuild the clock ($BIGW -> $FONTW)"
    FAIL=1
fi
echo "--- zoned clock: $ZONED"
if [ "$ZONED" = "zone 1 label ОКЛ shown 1 mute 0 small 1" ]; then
    echo "OK: a zoned clock tells the zone's time in the zone's own words,\
 and the tiny label is worn only where it was SAID — the zone glued\
 nothing onto the mute one"
else
    echo "FAIL: the zoned clock answered {$ZONED}"; FAIL=1
fi
echo "--- heartbeats after three rebuilds: $BEATS"
if [ "$BEATS" = "туда 1 тихо 1" ]; then
    echo "OK: one heartbeat per widget — a rebuild supersedes the pending\
 chain, it does not stack one more"
else
    echo "FAIL: pending widget-tick per widget after three rebuilds:\
 {$BEATS}"; FAIL=1
fi
if grep -qE 'build failed|handler error' "$LOG"; then
    echo "FAIL: errors in the log:"; grep -E 'build failed|handler error' "$LOG"
    FAIL=1
fi
check_invariants "$LOG"
exit $FAIL
