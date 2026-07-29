# Demo client that asks for fullscreen BEFORE it is ever mapped — the
# EWMH path where the state is a PROPERTY on the window at manage time
# rather than a ClientMessage afterwards. argv = title color ?secs?.
#
# Tk's own `wm attributes -fullscreen` is what does it: on an unmapped
# toplevel it writes _NET_WM_STATE and leaves the WM to frame it right
# the first time. (xterm and kitty, measured, take the other road —
# they map first and then send the message.)
package require Tk
lassign $argv title color secs
if {$secs eq ""} { set secs 20 }
if {$title eq ""} { set title fs-client }
if {$color eq ""} { set color #ad7fa8 }
chan configure stdout -buffering line
wm withdraw .
wm title . $title
wm geometry . 300x160
label .l -text $title -background $color -font {Sans 14}
pack .l -expand 1 -fill both
wm attributes . -fullscreen 1
puts "FSCLIENT $title: asked for fullscreen while unmapped"
wm deiconify .
after 2000 {puts "FSCLIENT: size=[winfo width .]x[winfo height .]\
 root=+[winfo rootx .]+[winfo rooty .]"}
after [expr {$secs * 1000}] exit
vwait ::forever
