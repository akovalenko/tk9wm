# Leader for the refocus regression: maps, pops a transient dialog after
# 2.5 s, closes it at 5 s, exits at 6.5 s. The driver watches whom the WM
# refocuses at each step (the dialog close must give focus back to THIS
# window — its leader — not to whichever window was focused more
# recently).
package require Tk
chan configure stdout -buffering line

wm title . "лидер"
wm geometry . 260x160+0+0
label .l -text "лидер" -background #729fcf -font {Sans 13}
pack .l -expand 1 -fill both

# NB: no id self-reports here — winfo id gives Tk's INNER window, while
# the WM manages the wrapper; the driver maps actors by manage order.
after 2500 {
    toplevel .d
    wm title .d "диалог"
    wm transient .d .          ;# sets WM_TRANSIENT_FOR on the dialog
    wm geometry .d 200x120+0+0
    label .d.l -text "диалог" -background #fcaf3e
    pack .d.l -expand 1 -fill both
    update idletasks
    puts "CLIENT leader: dialog mapped"
}
after 5000 { destroy .d; puts "CLIENT leader: dialog closed" }
after 6500 { puts "CLIENT leader: exiting"; exit 0 }
vwait ::forever
