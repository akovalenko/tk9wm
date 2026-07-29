#!/bin/sh
# Regression for the panel geometry pack: the strip grows to the icon
# square the moment any button face resolves (mixed panels unify via
# the auto-badge placeholder), set-panel-side puts the strip on any of
# the four edges with the workarea carved there — and left and top move
# the workarea's ORIGIN, which is what everything that places a window
# reads — set-panel-preset stack puts the label under the icon, and
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
    set T [panel-tree default]
    set P [panel-window default]
    set line [font metrics TitleFont -linespace]
    set isz [panel-cfg default icon_size]
    set tk 0
    foreach w [array names ::frameof] {
        if {[string match геометрия* [client-title $w]]} { set tk $w }
    }
    update; update idletasks
    # --- bottom / row, mixed iconness
    gchk {bottom row: itemheight is icon-driven} \
        [expr {max($isz, $line) + 16}] [$T cget -itemheight]
    gchk {bottom row: thickness = itemheight + 2} \
        [expr {[$T cget -itemheight] + 2}] [winfo height $P]
    gchk {bottom row: workarea gives the strip away} \
        [list 0 0 800 [expr {600 - [winfo height $P]}]] [workarea]
    gchk {row: resolved face shrunk to the square} 48 \
        [image width [$T item element cget 1 C0 eBIcon -image]]
    gchk {badge letters come from the label} БЕ \
        [$T item element cget 2 C0 ePTxt -text]
    set bb [$T item bbox 2 C0 ePRect]
    set bh [expr {[lindex $bb 3] - [lindex $bb 1]}]
    gchk {badge height pinned to the icon square} $isz $bh
    # --- right side
    set-panel-side right
    update; update idletasks
    set thick [winfo width $P]
    gchk {right: the strip hugs the right edge} \
        [list 600 [expr {800 - $thick}] 0] \
        [list [winfo height $P] [winfo x $P] [winfo y $P]]
    gchk {right: workarea carves the right edge} \
        [list 0 0 [expr {800 - $thick}] 600] [workarea]
    gchk {right: items flow top-down} 1 \
        [expr {[lindex [$T item bbox 2] 1] >= [lindex [$T item bbox 1] 3]}]
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
    # --- left side: the mirror of right, and the one that moves the
    # workarea's ORIGIN. Everything that places a window reads that
    # rectangle, so a left strip is where an extent read as a far edge
    # shows up as a window under the panel.
    set-panel-side left
    update; update idletasks
    set thick [winfo width $P]
    gchk {left: the strip hugs the left edge} \
        [list 600 0 0] [list [winfo height $P] [winfo x $P] [winfo y $P]]
    gchk {left: the workarea STARTS at the strip} \
        [list $thick 0 [expr {800 - $thick}] 600] [workarea]
    if {$tk != 0} {
        maximize-toggle $tk
        update idletasks
        regexp {\+(-?\d+)\+(-?\d+)$} [wm geometry $::frameof($tk)] -> mx my
        gchk {left: maximize starts at the strip, not at the screen} \
            [list $thick [expr {800 - $thick - 12}]] \
            [list $mx [$::frameof($tk).slot cget -width]]
        maximize-toggle $tk
    } else {
        puts "GEO FAIL: no client to maximize"
        incr ::gchk_n
    }
    # --- top: horizontal like the bottom, and an origin like the left
    set-panel-side top
    update; update idletasks
    set thick [winfo height $P]
    gchk {top: the strip hugs the top edge} \
        [list 800 0 0] [list [winfo width $P] [winfo x $P] [winfo y $P]]
    gchk {top: the workarea starts BELOW the strip} \
        [list 0 $thick 800 [expr {600 - $thick}]] [workarea]
    gchk {top: items flow left-right again} 1 \
        [expr {[lindex [$T item bbox 2] 0] >= [lindex [$T item bbox 1] 2]}]
    set-panel-side right   ;# ...and back to the column the rest measures
    update; update idletasks
    set thick [winfo width $P]
    # --- stack preset
    set-panel-preset stack
    update; update idletasks
    gchk {stack: itemheight adds the label line} \
        [expr {$isz + 2 + $line + 16}] [$T cget -itemheight]
    gchk {stack: label sits under the icon} 1 \
        [expr {[lindex [$T item bbox 1 C0 eBTxt] 1] >= \
               [lindex [$T item bbox 1 C0 eBIcon] 3]}]
    # --- a COLUMN is not a row: what the right-edge strip owes the eye
    # (owner's report, 2026-07-29 — an icon button and a badge button
    # laid out differently, and the live indicator floating in the gap
    # between two buttons instead of belonging to one).
    set-tray off
    update; update idletasks
    lassign [$T item bbox 1 C0 eFace] ix1 iy1 ix2 iy2
    lassign [$T item bbox 2 C0 eFace] bx1 by1 bx2 by2
    gchk {stack: every face spans the same width} \
        [list $ix1 $ix2] [list $bx1 $bx2]
    gchk {stack: every face is the same height} \
        [expr {$iy2 - $iy1}] [expr {$by2 - $by1}]
    gchk {stack: the badge sits where the icon sits} \
        [expr {[lindex [$T item bbox 1 C0 eBIcon] 1] - $iy1}] \
        [expr {[lindex [$T item bbox 2 C0 ePRect] 1] - $by1}]
    foreach item {1 2} {
        lassign [$T item bbox $item C0 eFace] - - fx2 fy2
        lassign [$T item bbox $item C0 eLive] - - lx2 ly2
        gchk "stack: item $item — the indicator ends where its face does" \
            [list $fx2 $fy2] [list $lx2 $ly2]
    }
    set-panel-preset row
    update; update idletasks
    foreach item {1 2} {
        lassign [$T item bbox $item C0 eFace] - - fx2 fy2
        lassign [$T item bbox $item C0 eLive] - - lx2 ly2
        gchk "row: item $item — the indicator ends where its face does" \
            [list $fx2 $fy2] [list $lx2 $ly2]
    }
    # Alignment of the LABELS inside their (widened) cells. The cell is
    # what item bbox reports, so it cannot show this — the check is on
    # the layout option itself: west in a row, centred under an icon.
    gchk {row: labels stick to the left edge} \
        [list w w] [list [$T style layout sBtnI eBTxt -sticky] \
                         [$T style layout sBtnB eBTxt -sticky]]
    gchk {row: the badge button is as wide as the icon one} \
        [lrange [$T item bbox 1 C0 eFace] 0 0] \
        [lrange [$T item bbox 2 C0 eFace] 0 0]
    gchk {row: ...and ends in the same place} \
        [lrange [$T item bbox 1 C0 eFace] 2 2] \
        [lrange [$T item bbox 2 C0 eFace] 2 2]
    set-panel-preset stack
    update; update idletasks
    # ...and back to treectrl's own default (fill the cell), which is
    # what centres a label under the icon above it
    gchk {stack: labels stay centred under their icons} \
        [list wnes wnes] [list [$T style layout sBtnI eBTxt -sticky] \
                               [$T style layout sBtnB eBTxt -sticky]]

    # --- icon size knob
    set-panel-icon-size 32
    update; update idletasks
    gchk {icon-size knob re-targets the geometry} \
        [expr {32 + 2 + $line + 16}] [$T cget -itemheight]
    gchk {icon-size knob resamples the face} 32 \
        [image width [$T item element cget 1 C0 eBIcon -image]]
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
if [ "$PASS" = 31 ]; then
    echo "OK: all 31 checks passed"
else
    echo "FAIL: $PASS PASS lines, want 31"
fi
if grep -q 'GEO BATTERY: 31 checks' "$HERE/wm-panelgeo.log"; then
    echo "OK: the battery ran to completion"
else
    echo "FAIL: the battery is missing or truncated"
fi
if grep -q 'handler error' "$HERE/wm-panelgeo.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-panelgeo.log"
fi
