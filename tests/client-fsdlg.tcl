# Fullscreen leader with a transient: maps, goes fullscreen at 2 s, pops
# a dialog at 4 s and keeps both alive. For the fullscreen-layer test —
# a fullscreen window must not swallow its own dialog, and neither of
# them may hide under the panel while the pair is the active one.
#
# argv = ?title? ?colour? — a driver that already has an actor of that
# colour on the desk needs this one to be somebody else, or a pixel
# cannot say which of them it is looking at.
package require Tk
chan configure stdout -buffering line
lassign $argv title colour
if {$title eq ""} { set title "полный" }
if {$colour eq ""} { set colour #8ae234 }

wm title . $title
wm geometry . 300x200
label .l -text $title -background $colour -font {Sans 13}
pack .l -expand 1 -fill both
after 2000 {
    wm attributes . -fullscreen 1
    puts "CLIENT: fullscreen asked"
}
after 4000 {
    toplevel .d
    wm title .d "диалог"
    wm transient .d .
    wm geometry .d 240x140+400+300
    label .d.l -text "диалог" -background #fcaf3e -font {Sans 13}
    pack .d.l -expand 1 -fill both
    update idletasks
    puts "CLIENT: dialog mapped"
}
after 40000 exit
vwait ::forever
