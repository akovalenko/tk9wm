#!/bin/sh
# Regression for panels in the PLURAL: `panel NAME BODY` declares one,
# everything outside a block belongs to `default`, and the strips carve
# their bands out of the screen IN DECLARATION ORDER — so the corner
# between two edges goes to whoever was declared first and what
# survives is the workarea. Then the per-panel plumbing: buttons, the
# live judgement and a fire all reach the panel they belong to and no
# other, a panel moved to another edge re-carves every band, a window
# is born inside the workarea both panels left (the origin an extent
# read as a far edge would have lost), and the tray follows the panel
# it is told to ride.
. "$(dirname "$0")/common.sh"
export DISPLAY=:69
rm -f /tmp/.X69-lock /tmp/.X11-unix/X69
Xvfb :69 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

rm -rf "$HERE/panels-config"
mkdir -p "$HERE/panels-config"

cat > "$HERE/panels-config/tk9wm.tcl" <<'EOF'
# A dock down the LEFT edge, declared first, and the stock bar along
# the bottom — declared the way a config that never heard of the plural
# writes it, which is the back-compat half of this test.
action левая {match {filter -title {жилец*}}}
action нижняя {}
panel dock {
    set-panel-side left
    panel-button левая
}
panel-button нижняя
set-tray on

proc pchk {desc want got} {
    if {$got eq $want} {
        puts "PANELS PASS: $desc"
    } else {
        puts "PANELS FAIL: $desc (want $want, got $got)"
    }
    incr ::pchk_n
}
proc by-title {pat} {
    foreach w [array names ::frameof] {
        if {[string match $pat [client-title $w]]} { return $w }
    }
    return 0
}
proc frame-geo {w} {
    if {![info exists ::frameof($w)]} { return {} }
    if {[regexp {^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$} \
             [wm geometry $::frameof($w)] -> fw fh fx fy]} {
        return [list $fx $fy $fw $fh]
    }
    return {}
}
proc panels-battery {} {
    set ::pchk_n 0
    update; update idletasks
    set D [panel-window dock];  set DT [panel-tree dock]
    set B [panel-window default]; set BT [panel-tree default]
    pchk {two names, two strips} 1 \
        [expr {$D ne "" && $B ne "" && $D ne $B}]
    set dth [winfo width $D]
    set bth [winfo height $B]
    # --- the bands, and who gets the corner
    pchk {the dock hugs the left edge for the whole height} \
        [list 0 0 600] [list [winfo x $D] [winfo y $D] [winfo height $D]]
    pchk {the bar declared second starts where the dock ends} \
        [list $dth [expr {600 - $bth}] [expr {800 - $dth}]] \
        [list [winfo x $B] [winfo y $B] [winfo width $B]]
    pchk {the workarea is what both of them left} \
        [list $dth 0 [expr {800 - $dth}] [expr {600 - $bth}]] [workarea]
    # --- the buttons are each panel's own
    pchk {each panel holds its own buttons} [list 2 2] \
        [list [$DT item count] [$BT item count]]
    pchk {each button wears its own panel's label} [list левая нижняя] \
        [list [$DT item element cget 1 C0 eBTxt -text] \
              [$BT item element cget 1 C0 eBTxt -text]]
    pchk {the live judgement lands on the panel that matched} [list 1 0] \
        [list [expr {"live" in [$DT item state get 1]}] \
              [expr {"live" in [$BT item state get 1]}]]
    # --- a fire reaches one panel and not the other
    action-fire левая
    update; update idletasks
    pchk {a fire flashes the panel it was aimed at, alone} [list 1 0] \
        [list [expr {"found" in [$DT item state get 1]}] \
              [expr {"found" in [$BT item state get 1]}]]
    # --- the window born under both of them
    set tk [by-title жилец*]
    if {$tk != 0} {
        lassign [frame-geo $tk] fx fy fw fh
        pchk {a new window is born inside the workarea} 1 \
            [expr {$fx >= $dth && $fy >= 0
                   && $fx + $fw <= 800 && $fy + $fh <= 600 - $bth}]
        maximize-toggle $tk
        update idletasks
        pchk {maximize fills the workarea, corner and all} \
            [list $dth 0 [expr {800 - $dth}] [expr {600 - $bth}]] \
            [frame-geo $tk]
        maximize-toggle $tk
        # A list anchored by a button opens off the strip's INNER face,
        # whichever edge that strip is on — beside a vertical dock, not
        # off the screen edge it is glued to.
        winlist-open [list $tk] [list panel dock 0] chooser
        update; update idletasks
        pchk {a list anchored by the left dock opens beside it} 1 \
            [expr {[winfo exists .winlist] && [winfo x .winlist] >= $dth}]
        winlist-cancel
        update; update idletasks
    } else {
        puts "PANELS FAIL: no client on the desk"
        incr ::pchk_n 3
    }
    # --- the tray rides the panel it is told to
    pchk {the tray rides the default panel} bottom [tray-side]
    set-tray-panel dock
    update; update idletasks
    pchk {...and its edge follows when it is moved to the dock} left [tray-side]
    pchk {an empty tray reserves nothing either way} \
        [list $dth 0 [expr {800 - $dth}] [expr {600 - $bth}]] [workarea]
    set-tray-panel default
    update; update idletasks
    # --- a panel that changes edge re-carves every band
    panel dock { set-panel-side top }
    update; update idletasks
    set D [panel-window dock];  set DT [panel-tree dock]
    set B [panel-window default]; set BT [panel-tree default]
    set dth2 [winfo height $D]
    set bth2 [winfo height $B]
    pchk {the dock moved to the top spans the whole width} \
        [list 0 0 800] [list [winfo x $D] [winfo y $D] [winfo width $D]]
    pchk {the bar re-carved: the corner is still the dock's} \
        [list 0 [expr {600 - $bth2}] 800] \
        [list [winfo x $B] [winfo y $B] [winfo width $B]]
    pchk {the workarea followed both} \
        [list 0 $dth2 800 [expr {600 - $dth2 - $bth2}]] [workarea]
    panel dock { set-panel-side left }
    update; update idletasks
    puts "PANELS BATTERY: $::pchk_n checks"
}
wm-bind {<Super>p} panels-battery
EOF

XDG_CONFIG_HOME="$HERE/panels-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-panels.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" жилец-A 240x120 "#729fcf" "" "" 30 &
TK=$!
sleep 1.5

xdotool key super+p
sleep 1
import -display :69 -window root "$HERE/panels-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/panels-test.png"

kill $WM $TK 2>/dev/null

echo "--- battery lines:"
grep -E 'PANELS|panel .* up' "$HERE/wm-panels.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-panels.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'PANELS FAIL' "$HERE/wm-panels.log"; then
    echo "FAIL: battery failures present (above)"
else
    echo "OK: no battery failures"
fi
PASS=$(grep -c 'PANELS PASS' "$HERE/wm-panels.log")
if [ "$PASS" = 17 ]; then
    echo "OK: all 17 checks passed"
else
    echo "FAIL: $PASS PASS lines, want 17"
fi
if grep -q 'PANELS BATTERY: 17 checks' "$HERE/wm-panels.log"; then
    echo "OK: the battery ran to completion"
else
    echo "FAIL: the battery is missing or truncated"
fi
if grep -q 'handler error' "$HERE/wm-panels.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-panels.log"
fi
