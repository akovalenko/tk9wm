# A client that REFUSES its WM_DELETE_WINDOW: the close request is
# received, logged and ignored — the hung-app stand-in for the wink
# regression. (client.tcl exits on the same request; this one lives
# until its timer.)
package require Tk
chan configure stdout -buffering line
wm title . "молчун"
wm geometry . 240x140
wm protocol . WM_DELETE_WINDOW {puts "CLIENT: WM_DELETE_WINDOW ignored"}
label .l -text "не закроюсь" -background #ef2929 -font {Sans 13}
pack .l -expand 1 -fill both
after 20000 exit
vwait ::forever
