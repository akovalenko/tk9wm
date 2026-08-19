# A client whose position claim is the PROGRAM's, not the user's —
# PPosition, which every toolkit stamps on every window whether the
# program chose a position or not. Tk's own `wm geometry` claims
# USPosition, so the claim is restated with `wm positionfrom program`;
# the WM's own claim line says which one it read.
#
# argv = title geometry color ?secs? ?moveto?
package require Tk
lassign $argv title geom color secs moveto
if {$secs eq ""} { set secs 20 }
chan configure stdout -buffering line
wm title . $title
wm geometry . $geom
wm positionfrom . program
label .l -text $title -background $color -font {Sans 13}
pack .l -expand 1 -fill both
after 3000 {puts "PCLAIM $title: root=+[winfo rootx .]+[winfo rooty .]"}
if {$moveto ne ""} {
    # The claim is restated BEFORE the move — `wm geometry` would
    # otherwise put the user's flag back on and the request would be
    # answering a different question than the one under test.
    after 4000 {
        wm positionfrom . program
        update idletasks
    }
    after 4400 [list wm geometry . $moveto]
    after 4400 {wm positionfrom . program}
}
after [expr {$secs * 1000}] exit
vwait ::forever
