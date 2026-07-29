#!/bin/sh
# Regression for the panel geometry pack: the strip grows to the icon
# square the moment any button face resolves (mixed panels unify via
# the auto-badge placeholder), set-panel-side right turns it into a
# vertical strip on the right edge with the workarea carved there,
# set-panel-preset stack puts the label under the icon, and
# set-panel-icon-size re-targets both the geometry and the resample.
. "$(dirname "$0")/common.sh"
export DISPLAY=:91
rm -f /tmp/.X91-lock /tmp/.X11-unix/X91
Xvfb :91 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/panelgeo-config"
mkdir -p "$HERE/panelgeo-config/icons"

cat > "$HERE/panelgeo-config/make-png.tcl" <<'EOF'
package require Tk
lassign $argv path size color
image create photo p -width $size -height $size
p put $color -to 0 0 $size $size
p write $path -format png
exit
EOF
"$LINUX/whale" "$HERE/panelgeo-config/make-png.tcl" \
    "$HERE/panelgeo-config/icons/ff.png" 128 '#cc4444'

cat > "$HERE/panelgeo-config/tk9wm.tcl" <<'EOF'
set-icon-path [list __ICONS__]
panel-button терм {icon ff match {filter -title {геометрия*}}}
panel-button безикон {}
proc gchk {desc want got} {
    if {$got eq $want} {
        puts "GEO PASS: $desc"
    } else {
        puts "GEO FAIL: $desc (want $want, got $got)"
    }
    incr ::gchk_n
}
proc geo-battery {} {
    set ::gchk_n 0
    set line [font metrics TitleFont -linespace]
    set isz $::panel_icon_size
    set tk 0
    foreach w [array names ::frameof] {
        if {[string match геометрия* [client-title $w]]} { set tk $w }
    }
    update; update idletasks
    # --- bottom / row, mixed iconness
    gchk {bottom row: itemheight is icon-driven} \
        [expr {max($isz, $line) + 16}] [.panel.t cget -itemheight]
    gchk {bottom row: thickness = itemheight + 2} \
        [expr {[.panel.t cget -itemheight] + 2}] [winfo height .panel]
    gchk {bottom row: workarea gives the strip away} \
        [list 0 0 800 [expr {600 - [winfo height .panel]}]] [workarea]
    gchk {row: resolved face shrunk to the square} 48 \
        [image width [.panel.t item element cget 1 C0 eBIcon -image]]
    gchk {badge letters come from the label} БЕ \
        [.panel.t item element cget 2 C0 ePTxt -text]
    set bb [.panel.t item bbox 2 C0 ePRect]
    set bh [expr {[lindex $bb 3] - [lindex $bb 1]}]
    gchk {badge height pinned to the icon square} $isz $bh
    # --- right side
    set-panel-side right
    update; update idletasks
    set thick [winfo width .panel]
    gchk {right: the strip hugs the right edge} \
        [list 600 [expr {800 - $thick}] 0] \
        [list [winfo height .panel] [winfo x .panel] [winfo y .panel]]
    gchk {right: workarea carves the right edge} \
        [list 0 0 [expr {800 - $thick}] 600] [workarea]
    gchk {right: items flow top-down} 1 \
        [expr {[lindex [.panel.t item bbox 2] 1] >= [lindex [.panel.t item bbox 1] 3]}]
    if {$tk != 0} {
        maximize-toggle $tk
        update idletasks
        gchk {right: maximize stops at the strip} \
            [expr {800 - $thick - 12}] [$::frameof($tk).slot cget -width]
        maximize-toggle $tk
    } else {
        puts "GEO FAIL: no client to maximize"
        incr ::gchk_n
    }
    # --- stack preset
    set-panel-preset stack
    update; update idletasks
    gchk {stack: itemheight adds the label line} \
        [expr {$isz + 2 + $line + 16}] [.panel.t cget -itemheight]
    gchk {stack: label sits under the icon} 1 \
        [expr {[lindex [.panel.t item bbox 1 C0 eBTxt] 1] >= \
               [lindex [.panel.t item bbox 1 C0 eBIcon] 3]}]
    # --- a COLUMN is not a row: what the right-edge strip owes the eye
    # (owner's report, 2026-07-29 — an icon button and a badge button
    # laid out differently, and the live indicator floating in the gap
    # between two buttons instead of belonging to one).
    set-tray off
    update; update idletasks
    lassign [.panel.t item bbox 1 C0 eFace] ix1 iy1 ix2 iy2
    lassign [.panel.t item bbox 2 C0 eFace] bx1 by1 bx2 by2
    gchk {stack: every face spans the same width} \
        [list $ix1 $ix2] [list $bx1 $bx2]
    gchk {stack: every face is the same height} \
        [expr {$iy2 - $iy1}] [expr {$by2 - $by1}]
    gchk {stack: the badge sits where the icon sits} \
        [expr {[lindex [.panel.t item bbox 1 C0 eBIcon] 1] - $iy1}] \
        [expr {[lindex [.panel.t item bbox 2 C0 ePRect] 1] - $by1}]
    foreach item {1 2} {
        lassign [.panel.t item bbox $item C0 eFace] - - fx2 fy2
        lassign [.panel.t item bbox $item C0 eLive] - - lx2 ly2
        gchk "stack: item $item — the indicator ends where its face does" \
            [list $fx2 $fy2] [list $lx2 $ly2]
    }
    set-panel-preset row
    update; update idletasks
    foreach item {1 2} {
        lassign [.panel.t item bbox $item C0 eFace] - - fx2 fy2
        lassign [.panel.t item bbox $item C0 eLive] - - lx2 ly2
        gchk "row: item $item — the indicator ends where its face does" \
            [list $fx2 $fy2] [list $lx2 $ly2]
    }
    # Alignment of the LABELS inside their (widened) cells. The cell is
    # what item bbox reports, so it cannot show this — the check is on
    # the layout option itself: west in a row, centred under an icon.
    gchk {row: labels stick to the left edge} \
        [list w w] [list [.panel.t style layout sBtnI eBTxt -sticky] \
                         [.panel.t style layout sBtnB eBTxt -sticky]]
    gchk {row: the badge button is as wide as the icon one} \
        [lrange [.panel.t item bbox 1 C0 eFace] 0 0] \
        [lrange [.panel.t item bbox 2 C0 eFace] 0 0]
    gchk {row: ...and ends in the same place} \
        [lrange [.panel.t item bbox 1 C0 eFace] 2 2] \
        [lrange [.panel.t item bbox 2 C0 eFace] 2 2]
    set-panel-preset stack
    update; update idletasks
    # ...and back to treectrl's own default (fill the cell), which is
    # what centres a label under the icon above it
    gchk {stack: labels stay centred under their icons} \
        [list wnes wnes] [list [.panel.t style layout sBtnI eBTxt -sticky] \
                               [.panel.t style layout sBtnB eBTxt -sticky]]

    # --- icon size knob
    set-panel-icon-size 32
    update; update idletasks
    gchk {icon-size knob re-targets the geometry} \
        [expr {32 + 2 + $line + 16}] [.panel.t cget -itemheight]
    gchk {icon-size knob resamples the face} 32 \
        [image width [.panel.t item element cget 1 C0 eBIcon -image]]
    puts "GEO BATTERY: $::gchk_n checks"
    # leave the pretty state for the screenshot
    set-panel-icon-size 48
    update; update idletasks
}
wm-bind {<Super>g} geo-battery
EOF
sed -i "s|__ICONS__|$HERE/panelgeo-config/icons|g" "$HERE/panelgeo-config/tk9wm.tcl"

XDG_CONFIG_HOME="$HERE/panelgeo-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-panelgeo.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" геометрия-жилец 240x120 "#729fcf" "" "" 30 &
TK=$!
sleep 1.5

xdotool key super+g
sleep 1
import -display :91 -window root "$HERE/panelgeo-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/panelgeo-test.png"

kill $WM $TK 2>/dev/null

echo "--- battery lines:"
grep -E 'GEO|panel up' "$HERE/wm-panelgeo.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-panelgeo.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'GEO FAIL' "$HERE/wm-panelgeo.log"; then
    echo "FAIL: battery failures present (above)"
else
    echo "OK: no battery failures"
fi
PASS=$(grep -c 'GEO PASS' "$HERE/wm-panelgeo.log")
if [ "$PASS" = 25 ]; then
    echo "OK: all 25 checks passed"
else
    echo "FAIL: $PASS PASS lines, want 25"
fi
if grep -q 'GEO BATTERY: 25 checks' "$HERE/wm-panelgeo.log"; then
    echo "OK: the battery ran to completion"
else
    echo "FAIL: the battery is missing or truncated"
fi
if grep -q 'handler error' "$HERE/wm-panelgeo.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-panelgeo.log"
fi
