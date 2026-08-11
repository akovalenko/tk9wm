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
# The click that opens a calendar is not here yet, and the fork it
# faces is worth writing down while the widget is small: an in-process
# popup (popup-shell and grab-keys-to, the way the window menus work)
# or the first "mini-application" — a thread with its own Tk and its
# own X connection, which the WM would then frame like any client. The
# line wm-window already draws answers it: modal, short-lived, must not
# be a client -> the popup. A calendar one glances at and dismisses is
# exactly that. A calendar one keeps open, moves and switches to is a
# window, and should be a real client rather than something pretending.
# The two faces are DECLARED with the type (fonts below): the kin
# entry, the set-clock-font/set-date-font setters and the knobs in the
# configurator's fonts group all come from that one word — keep-fashion
# against a config's own wm-font included (шаг 84's disease, the cure
# now lives in widget-type-font).
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
}
