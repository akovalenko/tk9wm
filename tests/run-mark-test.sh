#!/bin/sh
# Regression for the mark laid over a panel button's face — the `badge`
# word of an action, one picture serving many deeds.
#
# What it pins — the first two reported from the live desk (2026-08-02),
# the third found while measuring them:
#  - a button that asked for NO mark draws nothing at all. The chip's
#    outline used to be fixed at element-creation time while only its
#    fill was dressed per item, so every unmarked icon wore an empty
#    chip as a black hairline;
#  - a button whose icon did not resolve — the pseudo-badge face, two
#    letters on a hashed colour — carries its mark like any other. The
#    mark elements used to live in the icon style alone, so a marked
#    badge button showed no mark whatsoever;
#  - and wherever it is drawn it hugs the lower-right corner of its own
#    face. Two ways it did not: in a stack the mark was walked in from
#    the item's left edge, which is the caption's edge there and not
#    the icon's; and an icon smaller than the strip's icon size (this
#    test's is, deliberately — 24px against the default) dragged the
#    mark off its corner, because the icon's cell was the picture while
#    every other number here is the icon SQUARE.
#
# All three presets at once, one panel each: row (default), stack and
# icons. Each strip carries the same four buttons — icon with a mark,
# icon without, badge with a mark, badge without.
. "$(dirname "$0")/common.sh"
start_xvfb

rm -rf "$HERE/mark-config"
mkdir -p "$HERE/mark-config"
cat > "$HERE/mark-config/tk9wm.tcl" <<'EOF'
# A hand-drawn face, so exactly two of the four buttons resolve an icon
# and the other two fall to the badge. A tk image name passes through
# the resolver untouched.
image create photo imgFace -width 24 -height 24
imgFace put #729fcf -to 0 0 24 24
imgFace put #204a87 -to 5 5 19 19

action лицо-меткой {icon imgFace badge t}
action лицо-голое  {icon imgFace}
action буквы-меткой {badge t}
action буквы-голые  {}

proc four-buttons {} {
    uplevel 1 {
        panel-button лицо-меткой
        panel-button лицо-голое
        panel-button буквы-меткой
        panel-button буквы-голые
    }
}
four-buttons
panel сверху {
    set-panel-side top
    set-panel-preset stack
    four-buttons
}
panel слева {
    set-panel-side left
    set-panel-preset icons
    four-buttons
}

proc mchk {desc want got} {
    if {$got eq $want} {
        puts "MARK PASS: $desc"
    } else {
        puts "MARK FAIL: $desc (want «$want», got «$got»)"
    }
    incr ::mchk_n
}
# What the chip on one button shows: its lettering and whether either
# of its two paints is on. Asking through cget and not through the log
# is the point — an element MISSING from the item's style errors here,
# which is the badge half of this test.
proc chip {panel aname} {
    set T [panel-tree $panel]
    if {$T eq ""} { return "no panel $panel" }
    if {![info exists ::panel_items($panel)]
            || ![dict exists $::panel_items($panel) $aname]} {
        return "no button $aname"
    }
    set item [dict get $::panel_items($panel) $aname]
    if {[catch {
        list [$T item element cget $item C0 eMark -text] \
             [expr {[$T item element cget $item C0 eMarkBg -fill] ne ""}] \
             [expr {[$T item element cget $item C0 eMarkBg -outline] ne ""}]
    } got]} { return "ERR: $got" }
    return $got
}
# Where the chip sits, as an offset from the FACE's lower-right corner
# — the corner it is supposed to hug. Positive means inside the face.
proc corner {panel aname} {
    set T [panel-tree $panel]
    set item [dict get $::panel_items($panel) $aname]
    if {[catch {$T item bbox $item C0 eBIcon} face]} {
        if {[catch {$T item bbox $item C0 ePRect} face]} { return "ERR: $face" }
    }
    if {[catch {$T item bbox $item C0 eMarkBg} chip]} { return "ERR: $chip" }
    if {![llength $face] || ![llength $chip]} { return "no bbox" }
    list [expr {[lindex $face 2] - [lindex $chip 2]}] \
         [expr {[lindex $face 3] - [lindex $chip 3]}]
}
proc mark-battery {} {
    set ::mchk_n 0
    update; update idletasks
    # WHERE it sits, and not merely that it is painted: the chip hugs
    # the lower-right corner of the face it annotates, on both faces
    # and in every preset. In a stack the caption is usually wider than
    # the icon, and a mark walked in from the item's edge landed in the
    # middle of the word instead.
    foreach panel {default сверху слева} {
        foreach a {лицо-меткой буквы-меткой} {
            set d [corner $panel $a]
            set near [expr {[llength $d] == 2
                && abs([lindex $d 0]) <= 3 && abs([lindex $d 1]) <= 3}]
            mchk "$panel: $a — chip in the face's corner (off by $d)" 1 $near
        }
    }
    foreach panel {default сверху слева} {
        # A mark asked for: the letter, and both paints on so it reads
        # over whatever is underneath.
        mchk "$panel: icon wears its mark"  {t 1 1} [chip $panel лицо-меткой]
        mchk "$panel: badge wears its mark" {t 1 1} [chip $panel буквы-меткой]
        # ...and none asked for: nothing drawn. The third element of
        # the triple is the hairline that was there.
        mchk "$panel: bare icon draws no chip"  {{} 0 0} [chip $panel лицо-голое]
        mchk "$panel: bare badge draws no chip" {{} 0 0} [chip $panel буквы-голые]
    }
    puts "MARK BATTERY: $::mchk_n checks"
}
wm-bind {<Super>b} mark-battery
EOF

XDG_CONFIG_HOME="$HERE/mark-config" \
    "$LINUX/whale" "$WMTCL" > "$HERE/wm-mark.log" 2>&1 &
WM=$!
sleep 1.5

xdotool key super+b
sleep 0.5
import -display "$DISPLAY" -window root "$HERE/mark-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/mark-test.png"

kill $WM 2>/dev/null

echo "--- battery lines:"
grep -E 'MARK ' "$HERE/wm-mark.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-mark.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if grep -q 'MARK BATTERY: 18 checks' "$HERE/wm-mark.log"; then
    echo "OK: the battery ran all eighteen checks"
else
    echo "FAIL: the battery did not run to the end"
fi
if grep -q 'MARK FAIL' "$HERE/wm-mark.log"; then
    echo "FAIL: battery failures present (above)"
else
    echo "OK: no battery failures"
fi
if grep -q 'handler error' "$HERE/wm-mark.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-mark.log"
fi
check_invariants "$HERE/wm-mark.log"
