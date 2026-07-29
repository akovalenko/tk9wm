# Demo client that REPORTS what the pointer does to it: argv = title
# geometry color ?secs?. Every button press and release inside the
# client is printed, which is how a test tells "the WM took this
# gesture" from "the WM let it through".
package require Tk
lassign $argv title geom color secs
if {$secs eq ""} { set secs 8 }
if {$title eq ""} { set title press }
if {$geom  eq ""} { set geom 240x120 }
if {$color eq ""} { set color #729fcf }
chan configure stdout -buffering line
wm title . $title
wm geometry . $geom
label .l -text $title -background $color -font {Sans 14}
pack .l -expand 1 -fill both
bind . <ButtonPress>   {puts "CLIENT $title: press %b at %x,%y state %s"}
bind . <ButtonRelease> {puts "CLIENT $title: release %b"}
after 3000 {puts "CLIENT $title: root=+[winfo rootx .]+[winfo rooty .]\
 size=[winfo width .]x[winfo height .]"}
after [expr {$secs * 1000}] exit
vwait ::forever
