# An APPLICATION, not a window: four toplevels up at once and all four
# down at once when it leaves — the lazarus-ide shape (the main bar, the
# object inspector, the source editor, a form). What the desk has to get
# right is the focus AFTER the burst, and the trap is that the pick made
# when the FIRST window goes names a sibling that is already dead on the
# server — its DestroyNotify simply has not been read yet.
#
# argv = ?secs? — how long the four stand before the app exits.
package require Tk
lassign $argv secs
if {$secs eq ""} { set secs 4 }
chan configure stdout -buffering line
wm title . стая0
wm geometry . 200x120+80+380
label .l -text стая0 -background #729fcf -font {Sans 12}
pack .l -expand 1 -fill both
foreach i {1 2 3} {
    toplevel .w$i
    wm title .w$i стая$i
    wm geometry .w$i 200x120+[expr {80 + 210 * $i}]+380
    label .w$i.l -text стая$i -background #ad7fa8 -font {Sans 12}
    pack .w$i.l -expand 1 -fill both
}
update idletasks
puts "BURST: four windows up"
# The trap, in its smallest honest form. Two windows go WITHDRAWN in
# ONE pass — which is how a toolkit application leaves (the LCL hides
# its forms; lazarus's own log says «client 0x… withdrew itself», never
# a destroy). Both unmaps reach the server together, so by the time the
# WM reads the FIRST one — «.», which Tk maps LAST and which therefore
# holds the focus — its sibling is ALREADY unviewable, and an unviewable
# window is one XSetInputFocus refuses. That sibling is .w1 on purpose:
# it is the most recently focused window after «.», so it is exactly
# whom the pick names. The other two stay standing, so there is
# somewhere honest for the focus to end up and the test can tell
# "recovered" from "the desk was empty anyway".
after [expr {$secs * 1000}] {
    puts "BURST: two windows leave together"
    wm withdraw .
    wm withdraw .w1
    update idletasks
    puts "BURST: withdrawn"
}
after [expr {$secs * 1000 + 6000}] { puts "BURST: leaving"; exit 0 }
vwait ::forever
