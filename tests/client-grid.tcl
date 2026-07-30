# Gridded demo client: declares WM_NORMAL_HINTS resize increments via
# wm grid — the natural 300x200 equals 30x20 cells of 10x10, so the
# base size is 0 and every increment-respecting WM resize lands on a
# multiple of 10. argv = title color ?+X+Y?
#
# The optional position is a CLAIM (USPosition, as any Tk `wm geometry`
# is) and exists for the reflow test, which needs a gridded window
# standing a known few pixels short of an edge — something no `place`
# rule can arrange, since a placement always lands its pinned edge
# exactly on the workarea's.
package require Tk
lassign $argv title color at
if {$title eq ""} { set title gridded }
if {$color eq ""} { set color #fce94f }
chan configure stdout -buffering line
wm title . $title
frame .f -width 300 -height 200 -background $color
pack .f -expand 1 -fill both
update idletasks          ;# the requested size must settle before wm grid math
wm grid . 30 20 10 10     ;# base = 300 - 30*10 = 0, inc 10x10
if {$at ne ""} { wm geometry . $at }
after [expr {[llength $argv] > 3 ? [lindex $argv 3] * 1000 : 8000}] exit
vwait ::forever
