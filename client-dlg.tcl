# Client with a TRANSIENT dialog — the shape GIMP's "Quit" dialog has:
# a main window plus a toplevel carrying WM_TRANSIENT_FOR pointing at it.
# argv: main-geometry dialog-geometry
package require Tk
lassign $argv mgeom dgeom
if {$mgeom eq ""} { set mgeom 300x200+20+20 }
if {$dgeom eq ""} { set dgeom 260x180+0+0 }
chan configure stdout -buffering line

wm title . "главное"
wm geometry . $mgeom
label .l -text "главное окно" -background #729fcf -font {Sans 13}
pack .l -expand 1 -fill both

after 2000 {
    toplevel .d
    wm title .d "диалог"
    wm transient .d .          ;# sets WM_TRANSIENT_FOR on the dialog
    wm geometry .d $dgeom
    label .d.l -text "диалог с кнопкой у нижнего края" -background #fcaf3e \
        -font {Sans 11} -wraplength 220
    pack .d.l -expand 1 -fill both
    button .d.b -text "КНОПКА" -command {puts "CLIENT: dialog button pressed"}
    pack .d.b -side bottom -fill x
    update idletasks
    puts "CLIENT: dialog mapped, transient for [winfo id .]"
}
after 5000 {
    puts "CLIENT: main root=+[winfo rootx .]+[winfo rooty .]\
 dialog root=+[winfo rootx .d]+[winfo rooty .d]\
 [winfo width .d]x[winfo height .d]"
}
after 7000 exit
vwait ::forever
