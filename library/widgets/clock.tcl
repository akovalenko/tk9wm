# The clock — the first widget, and the shape the others are meant to
# copy: two labels, a heartbeat, and no idea where it lives.
#
# The time is set larger than the date because that is what one reads
# from across the room, and both are DERIVED from the desk font rather
# than stated in points: 1.6 times the desk font and 0.8 times it stay
# in proportion when the desk font moves, which a pair of hard numbers
# would not (see the typography section in policy/10-look.tcl).
#
# It is also the WORKED EXAMPLE of the other half of the contract: the
# two lines go one above the other or side by side, and the clock
# decides which from what the desk told it about the strip (-band and
# -across, see widget.tcl). No idea where it lives, and still the right
# shape for the place — which is the whole point of telling the type
# instead of asking it.
#
# Its own options are DECLARED in the type's params below — kind,
# doc and default in one place, which is what puts them in the
# configurator and behind the vocabulary gate (see widget.tcl).
#
# The click that opens the CALENDAR (the end of this file) took the
# fork this paragraph used to hold open: an in-process popup, not the
# first "mini-application". The line wm-window already draws answers
# it — modal, short-lived, must not be a client -> the popup; a
# calendar one glances at and dismisses is exactly that. A calendar
# one KEEPS — moves, switches to, feeds a day's click into org-mode —
# would be a window and should be a real client; if that day comes it
# is a different thing, not this one grown.
# The faces are DECLARED with the type (fonts below): the kin
# entry, the set-clock-font/set-date-font/set-calendar-font setters
# and the knobs in the configurator's fonts group all come from that
# one word — keep-fashion against a config's own wm-font included
# (шаг 84's disease, the cure now lives in widget-type-font).
wm-widget-type clock {
    build clock-widget-build
    tick  clock-widget-tick
    every 1000
    prefers panel
    fonts {
        ClockFont {default {-size 1.6x -weight bold}
                   doc {the time's face, as a delta from the desk font}}
        DateFont  {default {-size 0.8x}
                   doc {the date line's face, as a delta from the desk font}}
        CalendarFont {default {-size 0.9x}
                      doc {the calendar sheet's face, as a delta from the desk font}}
    }
    params {
        -time-format {kind text default %H:%M
                      doc {a `clock format` string — the big line}
                      examples {%H:%M {the classic} %H:%M:%S {seconds too}}}
        -date-format {kind text default {%a %d %b}
                      doc {the smaller line — a `clock format` string too}
                      examples {{%a %d %b} {day, date, month}
                                %d.%m.%Y {numbers all the way}}}
    }
}

proc clock-widget-build {w opts} {
    set fg [dict get $opts -foreground]
    set bg [dict get $opts -background]
    label $w.time -font ClockFont -foreground $fg -background $bg -anchor center
    label $w.date -font DateFont  -foreground $fg -background $bg -anchor center
    # The text first, because the shape is decided on what it will say.
    clock-widget-tick $w $opts
    if {[clock-widget-shape $w $opts] eq "row"} {
        pack $w.time -side left
        pack $w.date -side left -padx [list $::clock_gap 0]
    } else {
        pack $w.time -side top -fill x
        pack $w.date -side top -fill x
    }
    # The click the header promised: the calendar, a toggle. Bound on
    # both labels as well as the frame — together they tile the face.
    set open [list calendar-toggle [dict get $opts -on]]
    foreach t [list $w $w.time $w.date] { bind $t <ButtonPress-1> $open }
}

# Air between the two lines when they lie side by side.
keep clock_gap 6

# WHICH WAY THE TWO LINES GO — all of what -band and -across buy, in
# one proc:
#
#   on a HORIZONTAL strip the thickness is HEIGHT, so the row is the
#   cheap shape and the stack is taken only when the strip is already
#   deep enough to hold it for nothing;
#   on a VERTICAL strip it is the other way round — the stack is the
#   narrow shape, and the row is taken when the paid width already
#   covers it. That second case is the one that makes -across worth
#   having: a vertical panel whose buttons lie ACROSS it is broad
#   already, and a clock squeezed into one line there would be paying
#   a price nobody was charging.
#
# With -across 0 both branches come out as "grow along the band", which
# is the approximation this started as — now a special case and not the
# rule.
proc clock-widget-shape {w opts} {
    # what the strip is charged for this widget besides the text: the
    # frame's own padding, and the border widget-claims-band counts.
    set edges [expr {2 * [dict get $opts -padding] + 2}]
    switch -- [dict get $opts -band] {
        horizontal {
            set stack [expr {[font metrics ClockFont -linespace]
                           + [font metrics DateFont -linespace] + $edges}]
            return [expr {[dict get $opts -across] >= $stack ? "stack" : "row"}]
        }
        vertical {
            set row [expr {[clock-widget-width ClockFont [$w.time cget -text]]
                         + [clock-widget-width DateFont [$w.date cget -text]]
                         + $::clock_gap + $edges}]
            return [expr {[dict get $opts -across] >= $row ? "row" : "stack"}]
        }
    }
    return stack   ;# on the desk nothing is scarce
}

# How wide the text can EVER get in this font, which is not how wide it
# is now: the digits of a proportional font differ in width, so a clock
# measured at 09:59 would change its mind one minute later. Its width
# still moves and widget-tick re-places it for that — what must not
# move is the shape.
proc clock-widget-width {font text} {
    set wide 0
    set fat 0
    foreach d {0 1 2 3 4 5 6 7 8 9} {
        set w [font measure $font $d]
        if {$w > $wide} { set wide $w; set fat $d }
    }
    set map {}
    foreach d {0 1 2 3 4 5 6 7 8 9} { lappend map $d $fat }
    font measure $font [string map $map $text]
}

proc clock-widget-tick {w opts} {
    # No fallbacks here: the params' defaults arrive merged into the
    # opts (widget-opts), so the declaration is the one place they live.
    set now [clock seconds]
    $w.time configure -text \
        [clock format $now -format [dict get $opts -time-format]]
    $w.date configure -text \
        [clock format $now -format [dict get $opts -date-format]]
    # The calendar rides this beat: redrawn whenever what it was drawn
    # from has moved (see calendar-signature).
    if {[winfo exists .calendar]
            && [calendar-signature] ne $::calendar_sig} {
        set on $::calendar_on
        calendar-close
        calendar-open $on
    }
}

# ---- the calendar: the click the header promised ----
#
# Three months on one sheet — the current one flanked by both its
# neighbours — in the workarea corner nearest the clock. The strip
# seats its widget area at the far end of the band (before the tray),
# so the corner is read off the panel's SIDE and nobody asks where the
# pointer is: a bottom or right panel's clock answers bottom right, a
# top panel's top right, a left panel's bottom left. A clock off any
# panel takes the default far corner, bottom right.
#
# No keyboard and no grab — a glance, not a conversation: the clock's
# click opens and closes it, a click on the sheet closes it too, and
# it is deliberately NOT in popups-close's modal set. That list is
# keyboard-modal by construction (the invariants insist), and this
# sheet holds no router to give back — putting it there would also
# release a router it never took, aborting whoever's key sequence was
# in flight.
proc calendar-toggle {on} {
    popups-close
    if {[winfo exists .calendar]} {
        set was $::calendar_on
        calendar-close
        # the same clock's click is a toggle; another clock's MOVES the
        # sheet to its own corner
        if {$was eq $on} return
    }
    calendar-open $on
}
proc calendar-close {} {
    if {![winfo exists .calendar]} return
    destroy .calendar
    puts "WM: calendar closed"
}
proc calendar-open {on} {
    set today [clock format [clock seconds] -format %Y-%m-%d]
    set first [clock scan [clock format [clock seconds] -format %Y-%m-01] \
                   -format %Y-%m-%d]
    set ::calendar_on $on
    toplevel .calendar -background $::OUTLINE
    wm overrideredirect .calendar 1
    # Withdrawn until it is measured AND placed: a fresh toplevel maps
    # on the first idle round, and the measuring update below runs one
    # — the sheet flashed up square at +0+0 before its geometry was
    # said (the owner, 2026-08-11).
    wm withdraw .calendar
    frame .calendar.f -background [themed raised]
    # a row of months along a horizontal strip, a column beside a
    # vertical one — the sheet lies the way its band runs
    set vert [calendar-vertical $on]
    set i 0
    foreach delta {-1 0 1} {
        set c [calendar-month .calendar.f.m$i \
                   [clock add $first $delta months] $today]
        if {$vert} {
            grid $c -row $i -column 0 -padx 4 -pady 4
        } else {
            grid $c -row 0 -column $i -padx 4 -pady 4
        }
        incr i
    }
    update idletasks
    set W [expr {[winfo reqwidth .calendar.f] + 2}]
    set H [expr {[winfo reqheight .calendar.f] + 2}]
    place .calendar.f -x 1 -y 1
    # FLUSH into the corner, no air: a gap there read as exactly a
    # client window's resize border, and this sheet does not resize
    # (the owner, 2026-08-11). The months' own grid padding is margin
    # enough for the eye.
    lassign [workarea] wx wy ww wh
    lassign [calendar-corner $on] halign valign
    set X [place-axis $wx $ww $W $halign]
    set Y [place-axis $wy $wh $H $valign]
    wm geometry .calendar ${W}x${H}+${X}+${Y}
    stack-layer .calendar $::LAYER_POPUP
    wm deiconify .calendar
    update idletasks
    bind .calendar <ButtonPress-1> calendar-close
    set ::calendar_sig [calendar-signature]
    puts "WM: calendar open ${W}x${H}+${X}+${Y}\
 ([clock format [clock add $first -1 months] -format %Y-%m] ..\
 [clock format [clock add $first 1 months] -format %Y-%m])"
}
# The workarea corner the sheet lands in, from the panel's side alone
# (see the header above).
proc calendar-corner {on} {
    if {[lindex $on 0] eq "panel"} {
        set p [lindex $on 1]
        if {$p eq ""} { set p default }
        switch -- [panel-cfg $p side] {
            top  { return {end start} }
            left { return {start end} }
        }
    }
    return {end end}
}
proc calendar-vertical {on} {
    if {[lindex $on 0] ne "panel"} { return 0 }
    set p [lindex $on 1]
    if {$p eq ""} { set p default }
    expr {[panel-cfg $p side] in {left right}}
}
# What the standing sheet was drawn FROM. The clock's tick reads it
# back — a calendar has a ticking clock by construction, it is its
# passenger — and redraws on any change: midnight, a theme flip, a
# workarea reshaped. Deliberately not a <Destroy> hook on the widget:
# the strip rebuilds whenever the time's own width moves a pixel,
# which with a proportional face is about once a minute, and a
# calendar that vanished with each rebuild would never survive a
# glance.
proc calendar-signature {} {
    list $::calendar_on [clock format [clock seconds] -format %Y-%m-%d] \
        [themed raised] [themed ink] [workarea]
}
# One month on one canvas: a title, the weekday header, the days —
# Monday first. Today wears the selection ground; the weekend columns
# write in the dim ink. Six day-rows ALWAYS, so the three sheets come
# out one height whatever their months span. The names come from the
# locale (-locale current follows LANG), the arithmetic from nothing
# but the first of the month.
proc calendar-month {c first today} {
    # the header names the week's days off any Monday whatever — and
    # the CELL is as wide as the widest of them wants: two digits fit
    # a Russian «Ср», not an English «Wed»
    set monday [clock add $first \
                    [expr {1 - [clock format $first -format %u]}] days]
    set names {}
    for {set i 0} {$i < 7} {incr i} {
        lappend names [clock format [clock add $monday $i days] \
                           -format %a -locale current]
    }
    set cw [expr {[font measure CalendarFont 00] + 10}]
    foreach n $names {
        set cw [expr {max($cw, [font measure CalendarFont $n] + 4)}]
    }
    set rh [expr {[font metrics CalendarFont -linespace] + 4}]
    set pad 8
    set W [expr {7*$cw + 2*$pad}]
    set H [expr {8*$rh + 2*$pad + 4}]
    canvas $c -background [themed raised] -highlightthickness 0 \
        -borderwidth 0 -width $W -height $H
    $c create text [expr {$W / 2}] [expr {$pad + $rh/2}] \
        -font CalendarFont -fill [themed ink] \
        -text [clock format $first -format {%B %Y} -locale current]
    set i 0
    foreach n $names {
        $c create text [expr {$pad + $i*$cw + $cw/2}] \
            [expr {$pad + $rh + 4 + $rh/2}] -font CalendarFont \
            -fill [themed dim] -text $n
        incr i
    }
    set dow0 [expr {[clock format $first -format %u] - 1}]
    set ndays [scan [clock format [clock add \
        [clock add $first 1 months] -1 days] -format %d] %d]
    set thismonth [expr {[string range $today 0 6] eq
                         [clock format $first -format %Y-%m]}]
    set daynow [scan [string range $today 8 9] %d]
    set y0 [expr {$pad + 2*$rh + 4}]
    for {set d 1} {$d <= $ndays} {incr d} {
        set cell [expr {$dow0 + $d - 1}]
        set x [expr {$pad + ($cell % 7)*$cw + $cw/2}]
        set y [expr {$y0 + ($cell / 7)*$rh + $rh/2}]
        set ink [expr {$cell % 7 >= 5 ? [themed dim] : [themed ink]}]
        if {$thismonth && $d == $daynow} {
            $c create rectangle [expr {$x - $cw/2 + 1}] \
                [expr {$y - $rh/2 + 1}] [expr {$x + $cw/2 - 1}] \
                [expr {$y + $rh/2 - 1}] -fill [themed select] -outline {}
            set ink [contrast-fg [themed select]]
        }
        $c create text $x $y -font CalendarFont -fill $ink -text $d
    }
    return $c
}
