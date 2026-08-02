# A client that decorates ITSELF — what every GTK4 window is. It asks
# for no frame the way they all do (_MOTIF_WM_HINTS with the
# decorations word zeroed, written before the window is ever mapped),
# and then moves itself the only way such a window can: by asking the
# WM to run the drag for it (EWMH _NET_WM_MOVERESIZE). Optionally it
# says WHAT it is instead and lets the decoration follow from that
# (_NET_WM_WINDOW_TYPE, through Tk's own -type).
#
#   argv = title geometry color ?motif? ?type? ?dragdir? ?secs?
#
# motif is the decorations WORD in decimal, "" to write no property at
# all: 0 asks for nothing, 8 (MWM_DECOR_TITLE) for a titlebar, 6
# (BORDER|RESIZEH) for a border and grips without one, 1
# (MWM_DECOR_ALL) for everything the long way round.
#
# dragdir, when given, is the EWMH direction the client asks for three
# seconds in — 8 is the move, 4 the bottom-right corner. The pointer is
# ungrabbed first, as the spec demands and as gdk does: our own drag
# cannot start while the client still holds the implicit grab its
# button press created.
package require Tk
lappend auto_path [file dirname [file dirname [file normalize [info script]]]]
package require tkwmx

lassign $argv title geom color motif wtype dragdir secs
if {$title eq ""} { set title csd }
if {$geom  eq ""} { set geom 240x120 }
if {$color eq ""} { set color #ad7fa8 }
if {$secs  eq ""} { set secs 8 }
chan configure stdout -buffering line

# WITHDRAWN while the hints go on: a decoration hint read after the
# map is a decoration already built, and the whole point is to be
# framed right the first time. Tk maps `.` at idle otherwise, and the
# race is not one to leave in a regression.
wm withdraw .
wm title . $title
wm geometry . $geom
label .l -text $title -background $color -font {Sans 14}
pack .l -expand 1 -fill both
if {$wtype ne ""} { wm attributes . -type $wtype }
update idletasks

# The window the MANAGER sees is not `winfo id .`: Tk keeps the WM
# properties on a WRAPPER, and that wrapper is the parent of the id a
# script gets handed (tkwmx::window tree says so out loud). A hint
# written on the inner window is written where nobody looks — and a
# ClientMessage naming it names a window the WM does not manage. It
# exists while the toplevel is still withdrawn, which is what makes
# hinting-before-mapping possible from Tk at all.
set id [lindex [tkwmx::window tree .] 1]
if {$motif ne ""} {
    # Five words, and the property's TYPE is the atom itself — not
    # CARDINAL, which is the detail that makes a hand-written reader
    # find nothing. flags=2 is MWM_HINTS_DECORATIONS alone: this
    # client says nothing about functions.
    set A [tkwmx::atom intern _MOTIF_WM_HINTS]
    tkwmx::prop set $id $A $A 32 [list 2 0 $motif 0 0]
}
wm deiconify .
puts "CSD $title: 0x[format %x $id] up, motif «$motif» type «$wtype»"

proc ask-drag {dir} {
    lassign [winfo pointerxy .] px py
    tkwmx::grab ungrab-pointer 0
    set root [lindex [tkwmx::window tree .] 0]
    set MR [tkwmx::atom intern _NET_WM_MOVERESIZE]
    # source=1 (a normal application), button 1, and the message is
    # ABOUT our window but SENT TO THE ROOT, where the manager listens.
    tkwmx::event client $::id $MR [list $px $py $dir 1 1] 32 \
        {substructure-notify substructure-redirect} $root
    puts "CSD: asked for direction $dir at +$px+$py"
}
if {$dragdir ne ""} { after 3000 [list ask-drag $dragdir] }

after 2500 {puts "CSD: root=+[winfo rootx .]+[winfo rooty .]\
 size=[winfo width .]x[winfo height .]"}
after [expr {$secs * 1000}] exit
vwait ::forever
