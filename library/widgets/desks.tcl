# The desk indicator — which of the desks one is on, and how many
# there are. The answer to "where am I" on a desk that has no pager
# and wants none (the owner, 2026-08-04): a pager is a map of windows
# one navigates by, and the window list is already that; what a
# desk-switching hand actually loses is the one fact this shows.
#
# Why not the key echo, which was the other candidate and is where a
# chord says what it did: the echo is CLEARED by the next press, and
# "you are on desk 2" has no moment at which it stops being true. A
# standing fact belongs in a standing place.
#
# Its own options are declared in the type's params below (kind, doc
# and default in one place — the configurator and the vocabulary gate
# both read them, see widget.tcl).
#
# It ticks on nothing: there is no clock in it, and the desk changing
# is an event the WM already has (policy-desk-changed calls
# widgets-tick-all). A widget that polled for this would be a widget
# that is wrong for up to a second every time.
wm-widget-type desks {
    build desks-widget-build
    tick  desks-widget-tick
    prefers panel
    fonts {
        DeskNumFont {default {-size 0.9x -weight bold}
                     doc {the marks' measure and the «2/4» lettering}}
    }
    params {
        -style {kind {choice dots text} default dots
                doc {a mark per desk, the current one filled — or «2/4» in words}}
        -gap   {kind {int 0} default 4
                doc {air between the marks, px}}
    }
}

proc desks-widget-build {w opts} {
    set fg [dict get $opts -foreground]
    set bg [dict get $opts -background]
    if {[dict get $opts -style] eq "text"} {
        label $w.n -font DeskNumFont -foreground $fg -background $bg \
            -anchor center
        pack $w.n -expand 1 -fill both
    } else {
        # One canvas rather than a label apiece: the marks are drawn
        # and re-drawn as a set, and a set of labels would have to be
        # created and destroyed every time the count changed.
        canvas $w.d -background $bg -highlightthickness 0 -borderwidth 0
        # NOT -fill: the canvas is exactly as big as the marks, and
        # what is left over is the cell's to centre it in. Filled, the
        # marks would sit against one edge of whatever room the strip
        # happened to give.
        pack $w.d -expand 1
    }
    desks-widget-tick $w $opts
}
# WHICH WAY THE MARKS GO — one rule, both strips, and it is the
# clock's own reasoning (-band and -across, see widget.tcl): a strip
# charges for its THICKNESS whether a widget uses it or not, so the
# marks lie ACROSS the band while they fit in what is already paid
# for, and along it when they do not.
#
# The owner's words for the two halves, a minute apart (2026-08-04):
# "не лучше ли точки по горизонтали, когда они помещаются в ширину
# панели" for a vertical strip, and then "а на горизонтальной наверное
# вертикально если влезает" — which is the same sentence about the
# other axis, so it is one rule and not two special cases. What it
# buys is LENGTH: the marks stop eating the bar the buttons live on.
#
# On the desk (no band at all) nothing is scarce and a row it is.
proc desks-widget-vertical {opts r gap} {
    set band [dict get $opts -band]
    if {$band ni {horizontal vertical}} { return 0 }
    set n $::ndesks
    set need [expr {$n * (2 * $r) + ($n - 1) * $gap + 1
                    + 2 * [dict get $opts -padding] + 2}]
    set fits [expr {[dict get $opts -across] >= $need}]
    # ACROSS a horizontal strip is a column; across a vertical one is
    # a row. Same wish, opposite words.
    expr {$band eq "horizontal" ? $fits : !$fits}
}
proc desks-widget-tick {w opts} {
    if {[winfo exists $w.n]} {
        $w.n configure -text "[desk-name $::desk]/$::ndesks"
        return
    }
    if {![winfo exists $w.d]} return
    set c $w.d
    set fg [dict get $opts -foreground]
    set gap [dict get $opts -gap]
    # The mark's size comes from the FONT, like everything else on this
    # desk: a dot the height of a lowercase letter sits right beside
    # text of the same size, whatever the desk font is set to.
    set r [expr {max(3, [font metrics DeskNumFont -linespace] / 4)}]
    set n $::ndesks
    set vert [desks-widget-vertical $opts $r $gap]
    set len [expr {$n * (2 * $r) + ($n - 1) * $gap}]
    set thick [expr {2 * $r}]
    # THE OUTLINE LIVES INSIDE THE BOX. A canvas outline straddles the
    # line it is drawn on, so both ends of a mark have to be half a
    # pixel IN — not the whole shape shifted half a pixel over, which
    # only moves the problem to the far side and clips there instead
    # (measured twice, the second time on the owner's own desk: "левый
    # обрезается снизу, второй и снизу и справа").
    $c configure -width [expr {($vert ? $thick : $len) + 1}] \
                 -height [expr {($vert ? $len : $thick) + 1}]
    $c delete all
    for {set i 0} {$i < $n} {incr i} {
        set off [expr {$i * (2 * $r + $gap)}]
        set x [expr {($vert ? 0 : $off) + 0.5}]
        set y [expr {($vert ? $off : 0) + 0.5}]
        # The one you are on is filled; the others are its outline, so
        # the row reads as one thing with a place in it rather than as
        # a filled mark and some unrelated rings.
        $c create oval $x $y [expr {$x + 2 * $r - 1}] [expr {$y + 2 * $r - 1}] \
            -outline $fg -width 1 \
            -fill [expr {$i == $::desk ? $fg : ""}] \
            -tags mark$i
    }
}
