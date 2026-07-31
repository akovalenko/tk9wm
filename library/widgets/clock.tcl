# The clock — the first widget, and the shape the others are meant to
# copy: two labels, a heartbeat, and no idea where it lives.
#
# The time is set larger than the date because that is what one reads
# from across the room, and both are DERIVED from the desk font rather
# than stated in points: 1.6 times the desk font and 0.8 times it stay
# in proportion when the desk font moves, which a pair of hard numbers
# would not (see the typography section in policy.tcl).
#
# Its own options, on top of the ones every widget takes:
#   -time-format   a `clock format` string, default %H:%M
#   -date-format   ...and the smaller line, default %a %d %b
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
# Keep-fashion, like the stock kin in policy.tcl: a re-source must
# not overwrite what a config wrote into these entries (шаг 84's
# disease, same cure).
unless-already {[dict exists $::font_kin ClockFont]} {
    wm-font ClockFont -size 1.6x -weight bold
}
unless-already {[dict exists $::font_kin DateFont]} {
    wm-font DateFont -size 0.8x
}

wm-widget-type clock {
    build clock-widget-build
    tick  clock-widget-tick
    every 1000
}

proc clock-widget-build {w opts} {
    set fg [dict get $opts -foreground]
    set bg [dict get $opts -background]
    label $w.time -font ClockFont -foreground $fg -background $bg -anchor center
    label $w.date -font DateFont  -foreground $fg -background $bg -anchor center
    pack $w.time -side top -fill x
    pack $w.date -side top -fill x
    clock-widget-tick $w $opts
}

proc clock-widget-tick {w opts} {
    set now [clock seconds]
    set tf %H:%M
    set df {%a %d %b}
    if {[dict exists $opts -time-format]} { set tf [dict get $opts -time-format] }
    if {[dict exists $opts -date-format]} { set df [dict get $opts -date-format] }
    $w.time configure -text [clock format $now -format $tf]
    $w.date configure -text [clock format $now -format $df]
}
