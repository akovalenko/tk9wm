# Gridded demo client: declares WM_NORMAL_HINTS resize increments via
# wm grid — the natural 300x200 equals 30x20 cells of 10x10, so the
# base size is 0 and every increment-respecting WM resize lands on a
# multiple of 10. argv = title color.
package require Tk
lassign $argv title color
if {$title eq ""} { set title gridded }
if {$color eq ""} { set color #fce94f }
chan configure stdout -buffering line
wm title . $title
frame .f -width 300 -height 200 -background $color
pack .f -expand 1 -fill both
update idletasks          ;# the requested size must settle before wm grid math
wm grid . 30 20 10 10     ;# base = 300 - 30*10 = 0, inc 10x10
after 8000 exit
vwait ::forever
