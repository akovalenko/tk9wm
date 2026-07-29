# A dialog that becomes transient LATE: the toplevel maps carrying no
# WM_TRANSIENT_FOR at all and aims itself at the leader only afterwards
# — the shape of a toolkit that realizes the parent after the dialog.
# The driver arranges a distractor window between the two maps, so the
# refocus after the dialog's death discriminates leader vs history.
package require Tk
chan configure stdout -buffering line
wm title . "лидер"
wm geometry . 260x160
label .l -text "лидер" -background #729fcf -font {Sans 13}
pack .l -expand 1 -fill both
after 2500 {
    toplevel .d
    wm title .d "потом-диалог"
    wm geometry .d 220x120
    label .d.l -text "диалог без лидера" -background #fcaf3e -font {Sans 11}
    pack .d.l -expand 1 -fill both
    update idletasks
    puts "CLIENT: leader [winfo id .] dialog [winfo id .d] (not transient yet)"
}
after 4500 {
    wm transient .d .
    puts "CLIENT: dialog aimed at the leader"
}
after 6500 {
    destroy .d
    puts "CLIENT: dialog destroyed"
}
after 9000 exit
vwait ::forever
