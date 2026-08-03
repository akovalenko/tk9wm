# Fullscreen leader with a transient: maps, goes fullscreen at 2 s, pops
# a dialog at 4 s and keeps both alive. For the fullscreen-layer test —
# a fullscreen window must not swallow its own dialog, and neither of
# them may hide under the panel while the pair is the active one.
package require Tk
chan configure stdout -buffering line

wm title . "полный"
wm geometry . 300x200
label .l -text "полный" -background #8ae234 -font {Sans 13}
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
